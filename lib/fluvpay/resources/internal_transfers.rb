# frozen_string_literal: true

require "uri"
require_relative "list_objects"
require "erb"

module FluvPay
  module Resources
    # Recurso de transferências internas (conta FluvPay para conta FluvPay).
    class InternalTransfers
      def initialize(client)
        @client = client
      end

      # Cria uma transferência interna FluvPay para FluvPay.
      #
      # Escopo exigido: +withdrawals.create+. Idempotency-Key gerado se omitido.
      # Não suportado em sandbox: chaves +fluv_test_+ recebem 403
      # (SANDBOX_NOT_SUPPORTED_FOR_TRANSFERS). Informe exatamente um entre
      # +recipient_email+ e +recipient_merchant_id+.
      #
      # @param amount_cents [Integer] valor em centavos (100..10000000).
      # @param recipient_email [String, nil] email do destinatário.
      # @param recipient_merchant_id [String, nil] ULID do merchant destinatário (26 chars).
      # @param description [String, nil] descrição (até 140 caracteres).
      # @param idempotency_key [String, nil] Idempotency-Key; gerado se omitido.
      # @return [Hash] a transferência criada.
      def create(amount_cents:, recipient_email: nil, recipient_merchant_id: nil,
                 description: nil, idempotency_key: nil)
        body = {
          "amount_cents" => amount_cents,
          "recipient_email" => recipient_email,
          "recipient_merchant_id" => recipient_merchant_id,
          "description" => description
        }
        key = idempotency_key || FluvPay::Client.new_idempotency_key
        @client.request(:post, "/internal-transfers/", body: body, idempotency_key: key)
      end

      # Lista transferências internas.
      #
      # Escopo exigido: +transfers.read+. Envelope: +limit+/+offset+.
      # @param direction [String, nil] "sent" (enviadas) ou "received" (recebidas).
      # @param limit [Integer, nil] itens por página (1..100).
      # @param offset [Integer, nil] deslocamento (>= 0).
      # @return [FluvPay::Resources::OffsetList] página com +.data+ e metadados.
      def list(direction: nil, limit: nil, offset: nil)
        params = {
          "direction" => direction,
          "limit" => limit,
          "offset" => offset
        }
        payload = @client.request(:get, "/internal-transfers/", params: params)
        OffsetList.new(payload)
      end

      # Recupera uma transferência interna por ID.
      #
      # @param transfer_id [String] identificador da transferência.
      # @return [Hash] a transferência.
      def retrieve(transfer_id)
        @client.request(:get, "/internal-transfers/#{ERB::Util.url_encode(transfer_id.to_s)}")
      end
    end
  end
end
