# frozen_string_literal: true

require_relative "test_helper"

# Testes dos três envelopes de paginação distintos do contrato.
class PaginationTest < Minitest::Test
  include FluvPayTestHelpers

  def test_charges_list_parseia_page_per_page
    body = {
      "data" => [{ "id" => "chg_1", "amount_cents" => 100, "currency" => "BRL", "status" => "paid", "created_at" => "2026-06-08T12:00:00Z" }],
      "page" => 2,
      "per_page" => 20,
      "total" => 41,
      "has_next" => true,
      "has_prev" => true
    }
    stub_request(:get, "#{BASE_URL}/charges/?page=2&per_page=20&status=paid")
      .to_return(status: 200, body: JSON.generate(body), headers: json_headers)

    client = build_client
    page = client.charges.list(page: 2, per_page: 20, status: "paid")
    assert_equal 2, page.page
    assert_equal 20, page.per_page
    assert_equal 41, page.total
    assert page.has_next?
    assert page.has_prev?
    assert_equal 1, page.data.size
    assert_equal "chg_1", page.data.first["id"]
    # Iterável via Enumerable.
    assert_equal ["chg_1"], page.map { |c| c["id"] }
  end

  def test_transactions_list_parseia_page_per_page
    body = {
      "data" => [{ "id" => "tx_1", "type" => "charge", "direction" => "credit" }],
      "page" => 1,
      "per_page" => 50,
      "total" => 1,
      "has_next" => false,
      "has_prev" => false
    }
    stub_request(:get, "#{BASE_URL}/transactions/?page=1&per_page=50")
      .to_return(status: 200, body: JSON.generate(body), headers: json_headers)

    client = build_client
    page = client.transactions.list(page: 1, per_page: 50)
    assert_equal 1, page.total
    refute page.has_next?
    refute page.has_prev?
    assert_equal "tx_1", page.data.first["id"]
  end

  def test_withdrawals_list_parseia_limit_offset
    body = {
      "data" => [{ "id" => "wd_1", "status" => "completed", "amount_cents" => 5000 }],
      "limit" => 10,
      "offset" => 20,
      "total" => 33
    }
    stub_request(:get, "#{BASE_URL}/withdrawals/?limit=10&offset=20")
      .to_return(status: 200, body: JSON.generate(body), headers: json_headers)

    client = build_client
    page = client.withdrawals.list(limit: 10, offset: 20)
    assert_equal 10, page.limit
    assert_equal 20, page.offset
    assert_equal 33, page.total
    assert_equal "wd_1", page.data.first["id"]
    # Envelope limit/offset não tem has_next.
    refute_respond_to page, :has_next?
  end

  def test_internal_transfers_list_parseia_limit_offset
    body = {
      "data" => [{ "id" => "itr_1", "status" => "completed", "amount_cents" => 2500 }],
      "limit" => 20,
      "offset" => 0,
      "total" => 1
    }
    stub_request(:get, "#{BASE_URL}/internal-transfers/?direction=sent&limit=20&offset=0")
      .to_return(status: 200, body: JSON.generate(body), headers: json_headers)

    client = build_client
    page = client.internal_transfers.list(direction: "sent", limit: 20, offset: 0)
    assert_equal 20, page.limit
    assert_equal 0, page.offset
    assert_equal 1, page.total
    assert_equal "itr_1", page.data.first["id"]
  end
end
