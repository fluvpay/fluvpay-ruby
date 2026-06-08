# frozen_string_literal: true

require "uri"
require_relative "list_objects"
require "erb"

module FluvPay
  module Resources
    # Recurso de saques PIX da conta para uma chave PIX.
    class Withdrawals
      def initialize(client)
        @client = client
      end

      # Cria um saque PIX.
      #
      # Escopo exigido: +withdrawals.create+. Idempotency-Key gerado se omitido.
      # Não suportado em sandbox: chaves +fluv_test_+ recebem 403
      # (SANDBOX_NOT_SUPPORTED_FOR_WITHDRAWALS).
      #
      # @param amount_cents [Integer] valor bruto em centavos (100..10000000).
      # @param pix_key [String] chave PIX de destino (1..140 caracteres).
      # @param pix_key_type [String] tipo da chave: cpf, cnpj, email, phone ou evp.
      # @param description [String, nil] descrição (até 140 caracteres).
      # @param idempotency_key [String, nil] Idempotency-Key; gerado se omitido.
      # @return [Hash] o saque criado.
      def create(amount_cents:, pix_key:, pix_key_type:, description: nil, idempotency_key: nil)
        body = {
          "amount_cents" => amount_cents,
          "pix_key" => pix_key,
          "pix_key_type" => pix_key_type,
          "description" => description
        }
        key = idempotency_key || FluvPay::Client.new_idempotency_key
        @client.request(:post, "/withdrawals/", body: body, idempotency_key: key)
      end

      # Lista saques.
      #
      # Escopo exigido: +withdrawals.read+. Envelope: +limit+/+offset+.
      # @param limit [Integer, nil] itens por página (1..100).
      # @param offset [Integer, nil] deslocamento (>= 0).
      # @param status [String, nil] filtra por status.
      # @return [FluvPay::Resources::OffsetList] página com +.data+ e metadados.
      def list(limit: nil, offset: nil, status: nil)
        params = {
          "limit" => limit,
          "offset" => offset,
          "status" => status
        }
        payload = @client.request(:get, "/withdrawals/", params: params)
        OffsetList.new(payload)
      end

      # Recupera um saque por ID.
      #
      # @param withdrawal_id [String] identificador do saque.
      # @return [Hash] o saque.
      def retrieve(withdrawal_id)
        @client.request(:get, "/withdrawals/#{ERB::Util.url_encode(withdrawal_id.to_s)}")
      end
    end
  end
end
