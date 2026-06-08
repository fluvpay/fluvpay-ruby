# frozen_string_literal: true

# FluvPay: SDK oficial em Ruby para a API de pagamentos PIX da FluvPay.
#
# Cobranças, saques, transferências internas, sandbox e verificação de
# webhooks por uma interface idiomática e previsível, construída apenas sobre
# a biblioteca padrão (net/http e json).
#
# @example Criar uma cobrança
#   require "fluvpay"
#
#   client = FluvPay::Client.new(api_key: "fluv_test_sua_chave")
#   charge = client.charges.create(amount_cents: 4990, description: "Pedido #1042")
#   puts charge["pix_copy_paste"]
module FluvPay
end

require_relative "fluvpay/version"
require_relative "fluvpay/errors"
require_relative "fluvpay/webhooks"
require_relative "fluvpay/client"
