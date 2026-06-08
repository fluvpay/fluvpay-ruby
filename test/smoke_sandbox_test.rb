# frozen_string_literal: true

require_relative "test_helper"

# Smoke test no sandbox real (gated). Só roda se a env +FLUVPAY_TEST_KEY+
# (prefixo +fluv_test_+) estiver presente; caso contrário, é pulado.
# Faz rede de verdade contra a API, então reativa as conexões do WebMock.
class SmokeSandboxTest < Minitest::Test
  def setup
    @api_key = ENV["FLUVPAY_TEST_KEY"]
    skip "FLUVPAY_TEST_KEY ausente: smoke do sandbox pulado." if @api_key.nil? || @api_key.empty?
    unless @api_key.start_with?("fluv_test_")
      skip "FLUVPAY_TEST_KEY não é uma chave de sandbox (fluv_test_); smoke pulado."
    end

    WebMock.allow_net_connect! if defined?(WebMock)
    base = ENV["FLUVPAY_BASE_URL"] || FluvPay::Client::DEFAULT_BASE_URL
    @client = FluvPay::Client.new(api_key: @api_key, base_url: base)
  end

  def teardown
    WebMock.disable_net_connect! if defined?(WebMock)
  end

  def test_cria_recupera_lista_e_reseta
    # Limpa o sandbox antes de começar.
    @client.sandbox.reset

    created = @client.charges.create(amount_cents: 4990, description: "Smoke SDK Ruby")
    refute_nil created["id"]
    assert_equal "pix", created["payment_method"]

    fetched = @client.charges.retrieve(created["id"])
    assert_equal created["id"], fetched["id"]

    page = @client.charges.list(per_page: 5)
    assert page.data.any? { |c| c["id"] == created["id"] }

    result = @client.sandbox.reset
    assert result["reset"]
  end
end
