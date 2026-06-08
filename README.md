# FluvPay Ruby

SDK oficial da FluvPay para Ruby. Pagamentos PIX, saques, transferências internas e verificação de webhooks, com erros tipados e tratamento idiomático.

- Ruby 3.0+
- Cliente HTTP sobre a biblioteca padrão (`net/http`), sem dependências de runtime
- Retries automáticos (apenas em operações seguras), Idempotency-Key gerada sozinha, erros tipados

## Instalação

A gem ainda não está publicada no RubyGems. Por enquanto, instale direto do código-fonte no GitHub. Esse é o método que funciona hoje.

### Via Bundler (recomendado)

Adicione ao seu `Gemfile`, fixando uma versão pela tag:

```ruby
gem "fluvpay", git: "https://github.com/fluvpay/fluvpay-ruby", tag: "v1.0.0"
```

E rode:

```bash
bundle install
```

Fixar a `tag` garante builds reproduzíveis. Se preferir acompanhar o desenvolvimento, troque `tag:` por `branch: "main"`, ciente de que a `main` pode mudar a qualquer momento.

### Sem Bundler

Para instalar a gem a partir do código-fonte sem um `Gemfile`:

```bash
git clone --branch v1.0.0 https://github.com/fluvpay/fluvpay-ruby.git
cd fluvpay-ruby
gem build fluvpay.gemspec
gem install ./fluvpay-1.0.0.gem
```

### Pelo RubyGems (em breve, quando publicado no RubyGems)

Assim que a gem for publicada no RubyGems, a instalação passará a ser por um destes caminhos. Eles ainda NÃO funcionam hoje:

```ruby
gem "fluvpay"
```

```bash
gem install fluvpay
```

## Autenticação

Use sua API Key no construtor. O modo (produção ou sandbox) vem do prefixo da chave: `fluv_live_` para produção e `fluv_test_` para o sandbox.

```ruby
require "fluvpay"

client = FluvPay::Client.new(api_key: "fluv_live_sua_chave_aqui")
```

A base URL padrão é `https://api.fluvpay.com/api/v1` e pode ser trocada com `base_url:`.

## Exemplo completo (copiável)

```ruby
require "fluvpay"

client = FluvPay::Client.new(api_key: "fluv_test_sua_chave_de_teste")

# 1. Criar uma cobrança PIX.
#    O valor vai em centavos. A Idempotency-Key é gerada automaticamente.
begin
  charge = client.charges.create(
    amount_cents: 5000,
    description: "Pedido 123",
    customer: { name: "Maria", email: "maria@exemplo.com" },
    metadata: { pedido_id: "123" }
  )
rescue FluvPay::ValidationError => err
  puts "Dados inválidos: #{err.code} #{err.message}"
  err.details.each { |d| puts " - #{d['field']} #{d['message']}" }
  raise
end

puts "Cobrança criada: #{charge['id']} #{charge['status']}"
puts "Copia e cola PIX: #{charge['pix_copy_paste']}"

# 2. Recuperar pela ID.
mesma = client.charges.retrieve(charge["id"])
puts "Status atual: #{mesma['status']}"

# 3. Listar cobranças (paginação page/per_page).
pagina = client.charges.list(page: 1, per_page: 20, status: "paid")
puts "Página #{pagina.page} de #{pagina.total} cobranças, há mais? #{pagina.has_next?}"
pagina.each { |item| puts " - #{item['id']} #{item['amount_cents']} #{item['status']}" }

# 4. Verificar a assinatura de um webhook recebido.
#    Use o corpo CRU da requisição, nunca o JSON re-serializado.
def handle_webhook(raw_body, headers)
  event = FluvPay::Webhooks.verify_signature(
    raw_body,
    headers["X-FluvPay-Signature"],
    headers["X-FluvPay-Timestamp"],
    "whsec_seu_segredo_do_webhook",
    event_type: headers["X-FluvPay-Event"],
    delivery_id: headers["X-FluvPay-Delivery-Id"],
    tolerance_seconds: 300
  )
  puts "Cobrança paga: #{event.data['id']}" if event.type == "charge.paid"
end
```

## Recursos e operações

Charges (cobranças PIX):

```ruby
client.charges.create(amount_cents:, idempotency_key: nil, **campos)  # POST /charges/
client.charges.retrieve(charge_id)                                    # GET  /charges/{id}
client.charges.list(page:, per_page:, sort:, status:)                 # GET  /charges/
```

Transactions (extrato):

```ruby
client.transactions.list(page:, per_page:, sort:)   # GET /transactions/
client.transactions.retrieve(tx_id)                 # GET /transactions/{id}
```

Withdrawals (saques PIX, somente produção):

```ruby
client.withdrawals.create(amount_cents:, pix_key:, pix_key_type:, idempotency_key: nil)  # POST /withdrawals/
client.withdrawals.list(limit:, offset:, status:)                                        # GET  /withdrawals/
client.withdrawals.retrieve(withdrawal_id)                                               # GET  /withdrawals/{id}
```

Internal Transfers (transferências FluvPay para FluvPay, somente produção):

```ruby
client.internal_transfers.create(amount_cents:, recipient_email:, idempotency_key: nil)  # POST /internal-transfers/
client.internal_transfers.list(direction:, limit:, offset:)                              # GET  /internal-transfers/
client.internal_transfers.retrieve(transfer_id)                                          # GET  /internal-transfers/{id}
```

Sandbox (apenas com chave `fluv_test_`):

```ruby
client.sandbox.reset       # POST /test/reset
client.sandbox.scenarios   # GET  /test/scenarios
```

## Criar uma cobrança: campos aceitos

O `charges.create` aceita exatamente os campos do contrato. Não envie `currency` nem `method`: a API rejeita com 422.

| Campo | Tipo | Observação |
|---|---|---|
| `amount_cents` | Integer, obrigatório | 100 a 100000 (R$ 1,00 a R$ 1.000,00) |
| `description` | String | até 500 caracteres |
| `customer` | Hash | `{ name:, email:, document:, phone: }` |
| `expires_in_seconds` | Integer | 60 a 604800 |
| `affiliate_code` | String | 4 a 24 caracteres |
| `split_rule_id` | String | 20 a 32 caracteres |
| `pass_fee_to_payer` | Boolean | padrão `true` |
| `metadata` | Hash | objeto livre |

Status de uma cobrança: `pending`, `paid`, `expired`, `cancelled`, `refunded`.

## Paginação

São três envelopes distintos, expostos como objetos de página iteráveis:

- `charges.list` e `transactions.list`: `page`, `per_page`, `total`, `has_next?`, `has_prev?`.
- `withdrawals.list` e `internal_transfers.list`: `limit`, `offset`, `total`.

```ruby
page = client.withdrawals.list(limit: 10, offset: 0)
puts [page.limit, page.offset, page.total].inspect
page.each { |w| puts "#{w['id']} #{w['status']} #{w['net_cents']}" }
```

## Idempotência

Os POSTs de escrita (`charges.create`, `withdrawals.create`, `internal_transfers.create`) usam o header `Idempotency-Key`. Se você não passar uma, o SDK gera um UUIDv4. Reenviar a mesma chave devolve a resposta original; reutilizar a chave com um payload diferente resulta em `FluvPay::ConflictError` (`IDEMPOTENCY_CONFLICT`).

```ruby
chave = FluvPay::Client.new_idempotency_key
client.charges.create(amount_cents: 5000, idempotency_key: chave)
```

## Erros

Todos os erros herdam de `FluvPay::Error` e carregam `code`, `message`, `details`, `trace_id` e `status_code`.

| Status | Exceção |
|---|---|
| 400 / 422 | `FluvPay::ValidationError` |
| 401 | `FluvPay::AuthenticationError` |
| 403 | `FluvPay::PermissionError` |
| 404 | `FluvPay::NotFoundError` |
| 409 | `FluvPay::ConflictError` |
| 429 | `FluvPay::RateLimitError` (campo `retry_after`) |
| 5xx | `FluvPay::ServerError` |
| rede / timeout | `FluvPay::ConnectionError` |

```ruby
begin
  client.charges.list
rescue FluvPay::RateLimitError => err
  puts "Rate limit. Tente de novo em #{err.retry_after} segundos."
end
```

## Retries

Por padrão o SDK tenta novamente 2 vezes (backoff exponencial com jitter) apenas em operações seguras: GET e POSTs que carregam Idempotency-Key, e somente para 429 e 5xx ou falha de conexão. Em 429 ele respeita o header `Retry-After`.

```ruby
client = FluvPay::Client.new(api_key: "fluv_live_...", max_retries: 4)   # ajustar
client = FluvPay::Client.new(api_key: "fluv_live_...", max_retries: 0)   # desligar
```

## Webhooks

A FluvPay assina cada entrega. O header `X-FluvPay-Signature` traz `v1=<hex>`, onde:

```
hex = HMAC_SHA256(secret, "{timestamp}." + corpo_cru)
```

`secret` é o `whsec_...` exibido na criação do webhook, `timestamp` vem de `X-FluvPay-Timestamp` e `corpo_cru` é o corpo da requisição exatamente como recebido. Use sempre o corpo cru, nunca o JSON re-serializado.

```ruby
begin
  event = FluvPay::Webhooks.verify_signature(
    raw_body,
    request.headers["X-FluvPay-Signature"],
    request.headers["X-FluvPay-Timestamp"],
    "whsec_...",
    tolerance_seconds: 300
  )
rescue FluvPay::SignatureVerificationError
  halt 400, "assinatura inválida"
end
```

Eventos disponíveis: `charge.created`, `charge.paid`, `charge.expired`, `charge.cancelled`, `charge.refunded`, `payout.created`, `payout.completed`, `payout.failed`.

## Desenvolvimento

```bash
bundle install
rake test
```

Os testes unitários rodam sem rede (`net/http` mockado com WebMock). O smoke no sandbox roda somente se a env `FLUVPAY_TEST_KEY` (prefixo `fluv_test_`) estiver presente; caso contrário, é pulado.

## Licença

MIT.
