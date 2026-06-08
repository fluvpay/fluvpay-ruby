# frozen_string_literal: true

require "openssl"
require_relative "test_helper"

# Vetor determinístico de assinatura de webhook (sem rede).
class WebhooksTest < Minitest::Test
  # Vetor fixo, pré-computado e conferido contra o algoritmo do contrato:
  #   hex = HMAC_SHA256(secret, timestamp + "." + corpo_cru)
  SECRET = "whsec_test_secret_123"
  TIMESTAMP = "1718000000"
  RAW_BODY = '{"event":"charge.paid","data":{"id":"chg_01J0000000000000000000000","status":"paid"}}'
  EXPECTED_HEX = "83edd830417f9adac0df5e6f10f4069465a867da6b859ff4de15bb8d6cb52a29"
  SIGNATURE_HEADER = "v1=#{EXPECTED_HEX}"

  def test_vetor_bate_com_algoritmo_independente
    # Recalcula com OpenSSL puro: prova que o vetor não foi inventado.
    manual = OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new("SHA256"),
      SECRET,
      "#{TIMESTAMP}.#{RAW_BODY}"
    )
    assert_equal EXPECTED_HEX, manual
    assert_equal EXPECTED_HEX, FluvPay::Webhooks.compute_signature(SECRET, TIMESTAMP, RAW_BODY)
  end

  def test_verify_signature_retorna_evento
    event = FluvPay::Webhooks.verify_signature(
      RAW_BODY, SIGNATURE_HEADER, TIMESTAMP, SECRET,
      event_type: "charge.paid", delivery_id: "dlv_1"
    )
    assert_equal "charge.paid", event.type
    assert_equal "dlv_1", event.delivery_id
    assert_equal TIMESTAMP, event.timestamp
    assert_equal "chg_01J0000000000000000000000", event.data["id"]
    assert_equal "paid", event.data["status"]
  end

  def test_type_sai_do_corpo_quando_event_type_omitido
    event = FluvPay::Webhooks.verify_signature(RAW_BODY, SIGNATURE_HEADER, TIMESTAMP, SECRET)
    assert_equal "charge.paid", event.type
  end

  def test_assinatura_adulterada_lanca
    adulterada = "v1=#{'0' * 64}"
    assert_raises(FluvPay::SignatureVerificationError) do
      FluvPay::Webhooks.verify_signature(RAW_BODY, adulterada, TIMESTAMP, SECRET)
    end
  end

  def test_corpo_modificado_lanca
    assert_raises(FluvPay::SignatureVerificationError) do
      FluvPay::Webhooks.verify_signature("#{RAW_BODY} ", SIGNATURE_HEADER, TIMESTAMP, SECRET)
    end
  end

  def test_header_sem_v1_lanca
    assert_raises(FluvPay::SignatureVerificationError) do
      FluvPay::Webhooks.verify_signature(RAW_BODY, EXPECTED_HEX, TIMESTAMP, SECRET)
    end
  end

  def test_tolerancia_de_tempo_rejeita_antigo
    assert_raises(FluvPay::SignatureVerificationError) do
      FluvPay::Webhooks.verify_signature(
        RAW_BODY, SIGNATURE_HEADER, TIMESTAMP, SECRET, tolerance_seconds: 300
      )
    end
  end

  def test_tolerancia_aceita_recente
    now = Time.now.to_i.to_s
    sig = "v1=#{FluvPay::Webhooks.compute_signature(SECRET, now, RAW_BODY)}"
    event = FluvPay::Webhooks.verify_signature(
      RAW_BODY, sig, now, SECRET, tolerance_seconds: 300
    )
    assert_equal "charge.paid", event.type
  end

  def test_timestamp_nao_numerico_com_tolerancia_lanca
    sig = "v1=#{FluvPay::Webhooks.compute_signature(SECRET, 'abc', RAW_BODY)}"
    assert_raises(FluvPay::SignatureVerificationError) do
      FluvPay::Webhooks.verify_signature(RAW_BODY, sig, "abc", SECRET, tolerance_seconds: 300)
    end
  end
end
