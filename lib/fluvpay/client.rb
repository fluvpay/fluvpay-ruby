# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "openssl"
require "securerandom"

require_relative "version"
require_relative "errors"
require_relative "resources/charges"
require_relative "resources/transactions"
require_relative "resources/withdrawals"
require_relative "resources/internal_transfers"
require_relative "resources/sandbox"

module FluvPay
  # Cliente principal da FluvPay.
  #
  # Estilo Stripe: um objeto +FluvPay::Client+ configurado com a API key, expondo
  # recursos (+charges+, +transactions+, +withdrawals+, +internal_transfers+ e
  # +sandbox+). O transporte usa +net/http+ da biblioteca padrão, com retries
  # (apenas em GET e POSTs idempotentes), geração automática de Idempotency-Key
  # (UUIDv4) e mapeamento de erro tipado.
  #
  # @example
  #   client = FluvPay::Client.new(api_key: "fluv_test_sua_chave")
  #   charge = client.charges.create(amount_cents: 4990, description: "Pedido #1042")
  #   puts charge["pix_copy_paste"]
  class Client
    DEFAULT_BASE_URL = "https://api.fluvpay.com/api/v1"
    DEFAULT_TIMEOUT = 30
    DEFAULT_OPEN_TIMEOUT = 10
    DEFAULT_MAX_RETRIES = 2
    DEFAULT_BACKOFF_FACTOR = 0.5
    DEFAULT_MAX_BACKOFF = 8.0

    # @return [String] a API key configurada.
    attr_reader :api_key
    # @return [String] URL base sem barra final.
    attr_reader :base_url
    # @return [Integer] tentativas extras em 429/5xx/conexão.
    attr_reader :max_retries

    # Recursos expostos.
    attr_reader :charges, :transactions, :withdrawals, :internal_transfers, :sandbox

    # @param api_key [String] chave da API (+fluv_live_...+ ou +fluv_test_...+).
    # @param base_url [String] URL base (padrão: produção e sandbox unificados).
    # @param timeout [Numeric] timeout de leitura por requisição, em segundos.
    # @param open_timeout [Numeric] timeout de abertura de conexão, em segundos.
    # @param max_retries [Integer] tentativas extras (só GET e POSTs idempotentes).
    # @param backoff_factor [Float] fator do backoff exponencial com jitter.
    def initialize(api_key:, base_url: DEFAULT_BASE_URL, timeout: DEFAULT_TIMEOUT,
                   open_timeout: DEFAULT_OPEN_TIMEOUT, max_retries: DEFAULT_MAX_RETRIES,
                   backoff_factor: DEFAULT_BACKOFF_FACTOR)
      if !api_key.is_a?(String) || api_key.empty?
        raise ArgumentError, "api_key é obrigatória e deve ser uma string não vazia."
      end

      @api_key = api_key
      @base_url = base_url.to_s.sub(%r{/+\z}, "")
      @timeout = timeout
      @open_timeout = open_timeout
      @max_retries = max_retries
      @backoff_factor = backoff_factor

      @charges = Resources::Charges.new(self)
      @transactions = Resources::Transactions.new(self)
      @withdrawals = Resources::Withdrawals.new(self)
      @internal_transfers = Resources::InternalTransfers.new(self)
      @sandbox = Resources::Sandbox.new(self)
    end

    # @return [Boolean] true se a chave configurada for de sandbox (+fluv_test_+).
    def test_mode?
      self.class.test_key?(@api_key)
    end

    # @return [Boolean] true se a chave informada tiver prefixo +fluv_test_+.
    def self.test_key?(api_key)
      api_key.to_s.start_with?("fluv_test_")
    end

    # Gera um Idempotency-Key UUIDv4.
    # @return [String]
    def self.new_idempotency_key
      SecureRandom.uuid
    end

    # Executa uma requisição e devolve o JSON já parseado (ou lança erro tipado).
    #
    # @param method [Symbol, String] verbo HTTP (:get, :post).
    # @param path [String] caminho relativo à base_url (ex: "/charges/").
    # @param params [Hash, nil] parâmetros de query (valores nil são removidos).
    # @param body [Hash, nil] corpo JSON (valores nil são removidos no topo).
    # @param idempotency_key [String, nil] valor do header Idempotency-Key.
    # @param retry_request [Boolean, nil] força ou desliga o retry; nil = automático.
    # @return [Object] JSON parseado da resposta.
    def request(method, path, params: nil, body: nil, idempotency_key: nil, retry_request: nil)
      upper = method.to_s.upcase
      uri = build_uri(path, params)
      headers = default_headers
      headers["Idempotency-Key"] = idempotency_key unless idempotency_key.nil?

      payload = nil
      unless body.nil?
        headers["Content-Type"] = "application/json"
        payload = JSON.generate(clean_body(body))
      end

      retry_request = (upper == "GET" || (upper == "POST" && !idempotency_key.nil?)) if retry_request.nil?
      max_attempts = retry_request ? (@max_retries + 1) : 1

      attempt = 0
      last_exception = nil
      while attempt < max_attempts
        begin
          status, response, raw = perform(upper, uri, headers, payload)
        rescue Net::OpenTimeout, Net::ReadTimeout => e
          last_exception = e
          if should_retry_connection?(retry_request, attempt, max_attempts)
            sleep_backoff(attempt, nil)
            attempt += 1
            next
          end
          raise ConnectionError.new("Timeout ao conectar na FluvPay: #{e.message}")
        rescue SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError => e
          last_exception = e
          if should_retry_connection?(retry_request, attempt, max_attempts)
            sleep_backoff(attempt, nil)
            attempt += 1
            next
          end
          raise ConnectionError.new("Falha de conexão com a FluvPay: #{e.message}")
        end

        parsed = parse_json_body(raw)

        return parsed if status < 300

        if should_retry_status?(retry_request, status, attempt, max_attempts)
          sleep_backoff(attempt, retry_after_seconds(response))
          attempt += 1
          next
        end

        raise Errors.from_response(
          status,
          parsed.is_a?(Hash) ? parsed : nil,
          retry_after_header: header_value(response, "Retry-After")
        )
      end

      if last_exception
        raise ConnectionError.new(
          "Falha de conexão com a FluvPay após #{max_attempts} tentativas: #{last_exception.message}"
        )
      end
      raise ConnectionError.new("Falha de conexão com a FluvPay.")
    end

    private

    def default_headers
      {
        "Authorization" => "Bearer #{@api_key}",
        "User-Agent" => "fluvpay-ruby/#{FluvPay::VERSION}",
        "Accept" => "application/json"
      }
    end

    def build_uri(path, params)
      uri = URI.parse("#{@base_url}#{path}")
      cleaned = clean_params(params)
      uri.query = URI.encode_www_form(cleaned) if cleaned && !cleaned.empty?
      uri
    end

    def clean_params(params)
      return nil if params.nil?

      params.reject { |_, v| v.nil? }.transform_keys(&:to_s)
    end

    def clean_body(body)
      return body unless body.is_a?(Hash)

      body.reject { |_, v| v.nil? }
    end

    # Executa uma única chamada HTTP. Retorna [status, objeto_response, corpo_cru].
    def perform(method, uri, headers, payload)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @open_timeout
      http.read_timeout = @timeout

      request_class =
        case method
        when "GET" then Net::HTTP::Get
        when "POST" then Net::HTTP::Post
        else raise ArgumentError, "Método HTTP não suportado: #{method}"
        end

      req = request_class.new(uri.request_uri)
      headers.each { |k, v| req[k] = v }
      req.body = payload if payload

      response = http.request(req)
      [response.code.to_i, response, response.body]
    end

    def parse_json_body(raw)
      return nil if raw.nil? || raw.to_s.empty?

      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end

    def header_value(response, name)
      return nil unless response.respond_to?(:[])

      response[name]
    end

    def should_retry_connection?(retry_request, attempt, max_attempts)
      retry_request && attempt < max_attempts - 1
    end

    def should_retry_status?(retry_request, status, attempt, max_attempts)
      return false unless retry_request
      return false if attempt >= max_attempts - 1

      status == 429 || status >= 500
    end

    def retry_after_seconds(response)
      raw = header_value(response, "Retry-After")
      return nil if raw.nil?

      Float(raw)
    rescue ArgumentError, TypeError
      nil
    end

    def sleep_backoff(attempt, retry_after)
      delay =
        if !retry_after.nil? && retry_after >= 0
          retry_after
        else
          base = @backoff_factor * (2**attempt)
          jitter = rand * @backoff_factor
          [base + jitter, DEFAULT_MAX_BACKOFF].min
        end
      sleep(delay) if delay.positive?
    end
  end
end
