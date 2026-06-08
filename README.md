# FluvPay Ruby

SDK oficial da FluvPay para Ruby. Cobre cobranças PIX, saques, transferências internas e verificação de webhooks, com erros tipados e tratamento idiomático. A interface é estável e previsível, adequada tanto a integrações operadas por pessoas quanto a agentes que consomem a API de forma programática.

- Requer Ruby 3.0 ou superior.
- O cliente HTTP é construído sobre a biblioteca padrão (`net/http`). Não há dependências de runtime.
- Inclui retentativas automáticas em operações seguras, geração automática de `Idempotency-Key` e erros tipados por classe.

## Instalação

A gem está publicada no RubyGems. Via Bundler, adicione ao `Gemfile`:

```ruby
gem "fluvpay"
```

E execute:

```bash
bundle install
```

Sem Bundler, instale diretamente:

```bash
gem install fluvpay
```

### Instalação a partir do código-fonte

Para fixar uma versão específica pela tag em um `Gemfile`:

```ruby
gem "fluvpay", git: "https://github.com/fluvpay/fluvpay-ruby", tag: "v1.0.0"
```

Substituir `tag:` por `branch: "main"` acompanha o desenvolvimento em curso, com a ressalva de que a `main` pode mudar a qualquer momento.

Para construir a gem a partir do código-fonte sem um `Gemfile`:

```bash
git clone --branch v1.0.0 https://github.com/fluvpay/fluvpay-ruby.git
cd fluvpay-ruby
gem build fluvpay.gemspec
gem install ./fluvpay-1.0.0.gem
```

## Início rápido

```ruby
require "fluvpay"

client = FluvPay::Client.new(api_key: "fluv_test_sua_chave_de_teste")

charge = client.charges.create(
  amount_cents: 5000,
  description: "Pedido 123",
  customer: { name: "Maria", email: "maria@exemplo.com" },
  metadata: { pedido_id: "123" }
)

puts charge["id"]
puts charge["pix_copy_paste"]
```

## Autenticação

A autenticação usa a API Key informada no construtor do cliente. O ambiente é determinado pelo prefixo da chave: `fluv_live_` seleciona produção e `fluv_test_` seleciona o sandbox.

```ruby
require "fluvpay"

client = FluvPay::Client.new(api_key: "fluv_live_sua_chave_aqui")
```

A base URL padrão é `https://api.fluvpay.com/api/v1`. Para sobrescrevê-la, informe `base_url:` no construtor.

## Exemplo completo

O exemplo a seguir cria uma cobrança, recupera o registro, lista com paginação e verifica a assinatura de um webhook recebido.

```ruby
require "fluvpay"

client = FluvPay::Client.new(api_key: "fluv_test_sua_chave_de_teste")

# Criar uma cobrança PIX. O valor é informado em centavos.
# A Idempotency-Key é gerada automaticamente quando não fornecida.
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

# Recuperar pela ID.
mesma = client.charges.retrieve(charge["id"])
puts "Status atual: #{mesma['status']}"

# Listar cobranças com paginação page/per_page.
pagina = client.charges.list(page: 1, per_page: 20, status: "paid")
puts "Página #{pagina.page} de #{pagina.total} cobranças, há mais? #{pagina.has_next?}"
pagina.each { |item| puts " - #{item['id']} #{item['amount_cents']} #{item['status']}" }

# Verificar a assinatura de um webhook recebido.
# A verificação usa o corpo cru da requisição, nunca o JSON re-serializado.
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

## Referência de recursos

### Charges (cobranças PIX)

```ruby
client.charges.create(amount_cents:, idempotency_key: nil, **campos)  # POST /charges/
client.charges.retrieve(charge_id)                                    # GET  /charges/{id}
client.charges.list(page:, per_page:, sort:, status:)                 # GET  /charges/
```

### Transactions (extrato)

```ruby
client.transactions.list(page:, per_page:, sort:)   # GET /transactions/
client.transactions.retrieve(tx_id)                 # GET /transactions/{id}
```

### Withdrawals (saques PIX, somente produção)

```ruby
client.withdrawals.create(amount_cents:, pix_key:, pix_key_type:, idempotency_key: nil)  # POST /withdrawals/
client.withdrawals.list(limit:, offset:, status:)                                        # GET  /withdrawals/
client.withdrawals.retrieve(withdrawal_id)                                               # GET  /withdrawals/{id}
```

### Internal Transfers (transferências FluvPay para FluvPay, somente produção)

```ruby
client.internal_transfers.create(amount_cents:, recipient_email:, idempotency_key: nil)  # POST /internal-transfers/
client.internal_transfers.list(direction:, limit:, offset:)                              # GET  /internal-transfers/
client.internal_transfers.retrieve(transfer_id)                                          # GET  /internal-transfers/{id}
```

### Sandbox (somente com chave `fluv_test_`)

```ruby
client.sandbox.reset       # POST /test/reset
client.sandbox.scenarios   # GET  /test/scenarios
```

### Campos de `charges.create`

O método aceita exatamente os campos do contrato. Os campos `currency` e `method` não são aceitos: a API responde 422 quando enviados.

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

Os status possíveis de uma cobrança são `pending`, `paid`, `expired`, `cancelled` e `refunded`.

## Paginação

A API expõe dois formatos de envelope, ambos apresentados como objetos de página iteráveis:

- `charges.list` e `transactions.list` expõem `page`, `per_page`, `total`, `has_next?` e `has_prev?`.
- `withdrawals.list` e `internal_transfers.list` expõem `limit`, `offset` e `total`.

```ruby
page = client.withdrawals.list(limit: 10, offset: 0)
puts [page.limit, page.offset, page.total].inspect
page.each { |w| puts "#{w['id']} #{w['status']} #{w['net_cents']}" }
```

## Idempotência

Os POSTs de escrita (`charges.create`, `withdrawals.create` e `internal_transfers.create`) enviam o header `Idempotency-Key`. Quando a chave não é informada, o SDK gera um UUIDv4. Reenviar a mesma chave devolve a resposta original. Reutilizar a chave com um payload diferente resulta em `FluvPay::ConflictError` com código `IDEMPOTENCY_CONFLICT`.

```ruby
chave = FluvPay::Client.new_idempotency_key
client.charges.create(amount_cents: 5000, idempotency_key: chave)
```

## Webhooks

A FluvPay assina cada entrega. O header `X-FluvPay-Signature` contém `v1=<hex>`, calculado da seguinte forma:

```
hex = HMAC_SHA256(secret, "{timestamp}." + corpo_cru)
```

O `secret` é o valor `whsec_...` exibido na criação do webhook, o `timestamp` vem do header `X-FluvPay-Timestamp` e `corpo_cru` é o corpo da requisição exatamente como recebido. A verificação exige o corpo cru, nunca o JSON re-serializado.

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

Os eventos disponíveis são `charge.created`, `charge.paid`, `charge.expired`, `charge.cancelled`, `charge.refunded`, `payout.created`, `payout.completed` e `payout.failed`.

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
  puts "Rate limit. Tente novamente em #{err.retry_after} segundos."
end
```

## Retentativas

O SDK executa por padrão 2 retentativas com backoff exponencial e jitter. As retentativas ocorrem apenas em operações seguras: requisições GET e POSTs que carregam `Idempotency-Key`, e somente diante de respostas 429, 5xx ou falha de conexão. Em respostas 429, o header `Retry-After` é respeitado.

```ruby
client = FluvPay::Client.new(api_key: "fluv_live_...", max_retries: 4)   # aumentar
client = FluvPay::Client.new(api_key: "fluv_live_...", max_retries: 0)   # desativar
```

## Desenvolvimento

```bash
bundle install
rake test
```

Os testes unitários rodam sem acesso à rede, com `net/http` mockado via WebMock. O smoke test no sandbox roda somente quando a variável de ambiente `FLUVPAY_TEST_KEY` (prefixo `fluv_test_`) está presente; caso contrário, é pulado.

## Licença

MIT.
