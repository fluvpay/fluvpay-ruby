# frozen_string_literal: true

require "uri"
require_relative "list_objects"
require "erb"

module FluvPay
  module Resources
    # Recurso de extrato financeiro consolidado (entradas e saídas).
    class Transactions
      def initialize(client)
        @client = client
      end

      # Lista lançamentos do extrato.
      #
      # Escopos exigidos (qualquer um): +payments.read+, +transfers.read+ ou
      # +withdrawals.read+. Envelope: +page+/+per_page+.
      # Não suportado em sandbox: chaves +fluv_test_+ recebem 403.
      #
      # @param page [Integer, nil] página (1-based).
      # @param per_page [Integer, nil] itens por página (máx 100).
      # @param sort [String, nil] campo de ordenação (ex: "-created_at").
      # @return [FluvPay::Resources::PageList] página com +.data+ e metadados.
      def list(page: nil, per_page: nil, sort: nil)
        params = {
          "page" => page,
          "per_page" => per_page,
          "sort" => sort
        }
        payload = @client.request(:get, "/transactions/", params: params)
        PageList.new(payload)
      end

      # Recupera um lançamento por ID.
      #
      # @param tx_id [String] identificador do lançamento.
      # @return [Hash] o lançamento.
      def retrieve(tx_id)
        @client.request(:get, "/transactions/#{ERB::Util.url_encode(tx_id.to_s)}")
      end
    end
  end
end
