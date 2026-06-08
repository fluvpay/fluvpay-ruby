# frozen_string_literal: true

require_relative "test_helper"

# Testes diversos: create de saque/transferência, sandbox e helpers de chave.
class ResourcesMiscTest < Minitest::Test
  include FluvPayTestHelpers

  def test_client_exige_api_key
    assert_raises(ArgumentError) { FluvPay::Client.new(api_key: "") }
    assert_raises(ArgumentError) { FluvPay::Client.new(api_key: nil) }
  end

  def test_test_key_e_test_mode
    assert FluvPay::Client.test_key?("fluv_test_abc")
    refute FluvPay::Client.test_key?("fluv_live_abc")
    assert build_client.test_mode?
    refute FluvPay::Client.new(api_key: "fluv_live_x").test_mode?
  end

  def test_new_idempotency_key_gera_uuid
    key = FluvPay::Client.new_idempotency_key
    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/, key)
  end

  def test_withdrawal_create_envia_body_e_gera_key
    captured = nil
    stub_request(:post, "#{BASE_URL}/withdrawals/")
      .with { |req| captured = req; true }
      .to_return(status: 201,
                 body: JSON.generate({ "id" => "wd_1", "status" => "pending", "amount_cents" => 5000,
                                       "fee_cents" => 0, "net_cents" => 5000, "pix_key" => "x@y.com",
                                       "pix_key_type" => "email", "created_at" => "2026-06-08T12:00:00Z" }),
                 headers: json_headers)

    client = build_client
    result = client.withdrawals.create(amount_cents: 5000, pix_key: "x@y.com", pix_key_type: "email")

    sent = JSON.parse(captured.body)
    assert_equal 5000, sent["amount_cents"]
    assert_equal "x@y.com", sent["pix_key"]
    assert_equal "email", sent["pix_key_type"]
    refute sent.key?("description")
    refute_nil captured.headers["Idempotency-Key"]
    assert_equal "wd_1", result["id"]
  end

  def test_internal_transfer_create_envia_body
    captured = nil
    stub_request(:post, "#{BASE_URL}/internal-transfers/")
      .with { |req| captured = req; true }
      .to_return(status: 201,
                 body: JSON.generate({ "id" => "itr_1", "from_merchant_id" => "mer_a", "to_merchant_id" => "mer_b",
                                       "amount_cents" => 2500, "status" => "completed", "created_at" => "2026-06-08T12:00:00Z" }),
                 headers: json_headers)

    client = build_client
    result = client.internal_transfers.create(amount_cents: 2500, recipient_email: "loja@exemplo.com")

    sent = JSON.parse(captured.body)
    assert_equal 2500, sent["amount_cents"]
    assert_equal "loja@exemplo.com", sent["recipient_email"]
    refute sent.key?("recipient_merchant_id")
    assert_equal "completed", result["status"]
  end

  def test_sandbox_reset
    stub_request(:post, "#{BASE_URL}/test/reset")
      .to_return(status: 200,
                 body: JSON.generate({ "reset" => true, "deleted_charges" => 3, "merchant_id" => "mer_a" }),
                 headers: json_headers)

    client = build_client
    result = client.sandbox.reset
    assert result["reset"]
    assert_equal 3, result["deleted_charges"]
  end

  def test_sandbox_scenarios
    stub_request(:get, "#{BASE_URL}/test/scenarios")
      .to_return(status: 200,
                 body: JSON.generate({ "info" => "valores mágicos", "scenarios" => [{ "amount_cents" => 100 }] }),
                 headers: json_headers)

    client = build_client
    result = client.sandbox.scenarios
    assert_equal "valores mágicos", result["info"]
    assert_equal 1, result["scenarios"].size
  end

  def test_retrieve_escapa_id_com_caracteres_especiais
    stub_request(:get, "#{BASE_URL}/charges/chg%20a%2Fb")
      .to_return(status: 200, body: JSON.generate({ "id" => "ok" }), headers: json_headers)

    client = build_client
    result = client.charges.retrieve("chg a/b")
    assert_equal "ok", result["id"]
  end
end
