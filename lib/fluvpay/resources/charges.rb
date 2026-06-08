# frozen_string_literal: true

require "uri"
require_relative "list_objects"
require "erb"

module FluvPay
  module Resources
    # Recurso de cobranças PIX: criar, recuperar e listar.
    class Charges
      def initialize(client)
        @client = client
      end

      # Cria uma cobrança PIX.
      #
      # Escopo exigido: +payments.create+. O header +Idempotency-Key+ é
      # obrigatório na API; se não for informado, o SDK gera um UUIDv4
      # automaticamente.
      #
      # @param amount_cents [Integer] valor em centavos (100..100000), obrigatório.
      # @param description [String, nil] descrição (até 500 caracteres).
      # @param customer [Hash, nil] dados do pagador (name, email, document, phone).
      # @param expires_in_seconds [Integer, nil] expiração em segundos (60..604800).
      # @param affiliate_code [String, nil] código de afiliado (4..24 caracteres).
      # @param split_rule_id [String, nil] id de regra de split (20..32 caracteres).
      # @param pass_fee_to_payer [Boolean, nil] repassar a taxa ao pagador (default true).
      # @param metadata [Hash, nil] objeto livre de metadados.
      # @param idempotency_key [String, nil] Idempotency-Key; gerado se omitido.
      # @return [Hash] a cobrança criada.
      def create(amount_cents:, description: nil, customer: nil, expires_in_seconds: nil,
                 affiliate_code: nil, split_rule_id: nil, pass_fee_to_payer: nil,
                 metadata: nil, idempotency_key: nil)
        body = {
          "amount_cents" => amount_cents,
          "description" => description,
          "customer" => clean_customer(customer),
          "expires_in_seconds" => expires_in_seconds,
          "affiliate_code" => affiliate_code,
          "split_rule_id" => split_rule_id,
          "pass_fee_to_payer" => pass_fee_to_payer,
          "metadata" => metadata
        }
        key = idempotency_key || FluvPay::Client.new_idempotency_key
        @client.request(:post, "/charges/", body: body, idempotency_key: key)
      end

      # Recupera uma cobrança por ID.
      #
      # Escopo exigido: +payments.read+.
      # @param charge_id [String] identificador da cobrança.
      # @return [Hash] a cobrança.
      def retrieve(charge_id)
        @client.request(:get, "/charges/#{escape(charge_id)}")
      end

      # Lista cobranças.
      #
      # Escopo exigido: +payments.read+. Envelope: +page+/+per_page+.
      # @param status [String, nil] filtra por status.
      # @param page [Integer, nil] página (1-based).
      # @param per_page [Integer, nil] itens por página (máx 100).
      # @param sort [String, nil] campo de ordenação (ex: "-created_at").
      # @return [FluvPay::Resources::PageList] página com +.data+ e metadados.
      def list(status: nil, page: nil, per_page: nil, sort: nil)
        params = {
          "status" => status,
          "page" => page,
          "per_page" => per_page,
          "sort" => sort
        }
        payload = @client.request(:get, "/charges/", params: params)
        PageList.new(payload)
      end

      private

      def clean_customer(customer)
        return nil if customer.nil?

        customer.reject { |_, v| v.nil? }.transform_keys(&:to_s)
      end

      def escape(value)
        ERB::Util.url_encode(value.to_s)
      end
    end
  end
end
