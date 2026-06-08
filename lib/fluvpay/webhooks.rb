# frozen_string_literal: true

require "openssl"
require "json"

module FluvPay
  # Verificação de assinatura de webhooks da FluvPay.
  #
  # A FluvPay assina cada entrega com HMAC-SHA256 sobre +"{timestamp}." + corpo_cru+,
  # usando o segredo +whsec_...+ do webhook. O header +X-FluvPay-Signature+ traz
  # +v1=<hex>+. A verificação usa comparação em tempo constante e exige o corpo CRU
  # (a string exatamente como recebida), nunca reserializado.
  module Webhooks
    EVENT_HEADER = "X-FluvPay-Event"
    TIMESTAMP_HEADER = "X-FluvPay-Timestamp"
    DELIVERY_ID_HEADER = "X-FluvPay-Delivery-Id"
    SIGNATURE_HEADER = "X-FluvPay-Signature"

    # Eventos disponíveis (8). Espelha o catálogo do contrato OpenAPI.
    EVENT_TYPES = %w[
      charge.created
      charge.paid
      charge.expired
      charge.cancelled
      charge.refunded
      payout.created
      payout.completed
      payout.failed
    ].freeze

    # Evento de webhook já verificado e parseado, devolvido por
    # {FluvPay::Webhooks.verify_signature}.
    class Event
      # @return [String, nil] tipo do evento (ex: "charge.paid").
      attr_reader :type
      # @return [String, nil] identificador da entrega (X-FluvPay-Delivery-Id).
      attr_reader :delivery_id
      # @return [String] timestamp cru recebido (X-FluvPay-Timestamp).
      attr_reader :timestamp
      # @return [Hash] objeto "data" do evento (ou o payload inteiro como fallback).
      attr_reader :data
      # @return [Hash] payload completo parseado.
      attr_reader :raw

      def initialize(type:, delivery_id:, timestamp:, data:, raw:)
        @type = type
        @delivery_id = delivery_id
        @timestamp = timestamp
        @data = data
        @raw = raw
      end
    end

    module_function

    # Recalcula o hex da assinatura: HMAC_SHA256(secret, timestamp + "." + corpo_cru).
    #
    # @param secret [String] segredo do webhook (+whsec_...+).
    # @param timestamp [String] valor de +X-FluvPay-Timestamp+.
    # @param raw_body [String] corpo CRU da requisição.
    # @return [String] assinatura em hexadecimal.
    def compute_signature(secret, timestamp, raw_body)
      signed_payload = "#{timestamp}.#{raw_body}"
      OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), secret.to_s, signed_payload)
    end

    # Verifica a assinatura de um webhook e devolve o evento parseado.
    #
    # @param payload [String] corpo CRU da requisição, exatamente como recebido.
    # @param signature_header [String] valor de +X-FluvPay-Signature+ (formato +v1=<hex>+).
    # @param timestamp [String] valor de +X-FluvPay-Timestamp+.
    # @param secret [String] segredo do webhook (+whsec_...+).
    # @param tolerance_seconds [Integer, nil] se informado e o timestamp for numérico,
    #   rejeita entregas mais antigas que esse limite (proteção contra replay).
    # @param event_type [String, nil] valor de +X-FluvPay-Event+ (preenche Event#type).
    # @param delivery_id [String, nil] valor de +X-FluvPay-Delivery-Id+.
    # @return [FluvPay::Webhooks::Event] evento verificado.
    # @raise [FluvPay::SignatureVerificationError] assinatura ausente, inválida ou
    #   fora da tolerância de tempo.
    def verify_signature(payload, signature_header, timestamp, secret,
                         tolerance_seconds: nil, event_type: nil, delivery_id: nil)
      provided = extract_v1(signature_header.to_s)
      if provided.nil? || provided.empty?
        raise SignatureVerificationError.new(
          "Assinatura ausente ou em formato inválido (esperado 'v1=<hex>')."
        )
      end

      check_tolerance!(timestamp, tolerance_seconds) unless tolerance_seconds.nil?

      expected = compute_signature(secret, timestamp, payload)
      unless secure_compare(expected, provided)
        raise SignatureVerificationError.new("Assinatura do webhook não confere.")
      end

      parsed = parse_json(payload)
      resolved_type = event_type || (parsed.is_a?(Hash) ? parsed["event"] : nil)
      data =
        if parsed.is_a?(Hash) && parsed["data"].is_a?(Hash)
          parsed["data"]
        elsif parsed.is_a?(Hash)
          parsed
        else
          {}
        end

      Event.new(
        type: resolved_type,
        delivery_id: delivery_id,
        timestamp: timestamp,
        data: data,
        raw: parsed.is_a?(Hash) ? parsed : {}
      )
    end

    # Extrai o hex após +v1=+ (aceita vários esquemas separados por vírgula).
    def extract_v1(signature_header)
      return nil if signature_header.nil? || signature_header.empty?

      signature_header.split(",").each do |part|
        item = part.strip
        return item[3..].to_s.strip if item.start_with?("v1=")
      end
      nil
    end

    # Rejeita entregas fora da janela de tolerância (proteção contra replay).
    def check_tolerance!(timestamp, tolerance_seconds)
      ts_int =
        begin
          Integer(timestamp.to_s, 10)
        rescue ArgumentError, TypeError
          raise SignatureVerificationError.new(
            "Timestamp não numérico: impossível validar a tolerância de tempo."
          )
        end

      age = (Time.now.to_i - ts_int).abs
      return unless age > tolerance_seconds

      raise SignatureVerificationError.new(
        "Timestamp fora da tolerância (#{age}s > #{tolerance_seconds}s); possível replay."
      )
    end

    # Comparação de strings em tempo constante, resistente a timing attacks.
    def secure_compare(expected, provided)
      a = expected.to_s.b
      b = provided.to_s.b
      return false unless a.bytesize == b.bytesize

      OpenSSL.fixed_length_secure_compare(a, b)
    rescue StandardError
      # Fallback puro Ruby caso fixed_length_secure_compare não esteja disponível.
      bytes = a.unpack("C*")
      res = 0
      b.unpack("C*").each_with_index { |byte, i| res |= byte ^ bytes[i] }
      res.zero?
    end

    def parse_json(payload)
      text = payload.is_a?(String) ? payload : payload.to_s
      JSON.parse(text)
    rescue JSON::ParserError, TypeError
      {}
    end

    private_class_method :parse_json, :check_tolerance!
  end
end
