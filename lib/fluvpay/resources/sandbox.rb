# frozen_string_literal: true

module FluvPay
  module Resources
    # Utilitários de teste, disponíveis apenas com chave +fluv_test_+.
    class Sandbox
      def initialize(client)
        @client = client
      end

      # Apaga todos os dados do sandbox (só chave de teste).
      #
      # @return [Hash] resultado com +reset+, +deleted_charges+ e +merchant_id+.
      def reset
        @client.request(:post, "/test/reset")
      end

      # Lista os valores mágicos do sandbox.
      #
      # @return [Hash] com +info+ e a lista +scenarios+.
      def scenarios
        @client.request(:get, "/test/scenarios")
      end
    end
  end
end
