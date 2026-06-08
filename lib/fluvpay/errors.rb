# frozen_string_literal: true

module FluvPay
  # Exceção base de todos os erros do SDK.
  #
  # Carrega os campos do envelope de erro da API
  # (+{ "error": { code, message, details, trace_id } }+) além do status HTTP.
  # Toda exceção tipada do SDK herda desta classe, então um único
  # +rescue FluvPay::Error+ captura qualquer falha conhecida.
  class Error < StandardError
    # @return [String, nil] código canônico do erro (ex: "VALIDATION_ERROR").
    attr_reader :code
    # @return [Array<Hash>] lista de detalhes do erro (cada item com field/message/type).
    attr_reader :details
    # @return [String, nil] identificador da requisição para correlacionar nos logs.
    attr_reader :trace_id
    # @return [Integer, nil] status HTTP que originou o erro.
    attr_reader :status_code

    def initialize(message = nil, code: nil, details: nil, trace_id: nil, status_code: nil)
      super(message)
      @code = code
      @details = details || []
      @trace_id = trace_id
      @status_code = status_code
    end
  end

  # 400/422: payload ou parâmetros inválidos (VALIDATION_ERROR) ou estado
  # impeditivo (ex: INSUFFICIENT_BALANCE). Inspecione +#details+ para os campos.
  class ValidationError < Error; end

  # 401: autenticação ausente ou inválida (AUTHENTICATION_REQUIRED).
  class AuthenticationError < Error; end

  # 403: escopo insuficiente ou operação não permitida para a conta/ambiente
  # (PERMISSION_DENIED, API_KEY_INSUFFICIENT_SCOPE, SANDBOX_NOT_SUPPORTED_*).
  class PermissionError < Error; end

  # 404: recurso não encontrado (NOT_FOUND).
  class NotFoundError < Error; end

  # 409: conflito de idempotência (IDEMPOTENCY_CONFLICT), quando a mesma
  # Idempotency-Key é reutilizada com um payload diferente.
  class ConflictError < Error; end

  # 429: limite de requisições excedido (RATE_LIMITED).
  # +#retry_after+ traz os segundos sugeridos no header +Retry-After+.
  class RateLimitError < Error
    # @return [Float, nil] segundos a aguardar antes de tentar de novo.
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil, **kwargs)
      super(message, **kwargs)
      @retry_after = retry_after
    end
  end

  # 5xx: erro interno da FluvPay (SERVER_ERROR e afins).
  class ServerError < Error; end

  # Falha de rede, timeout ou conexão recusada antes de obter uma resposta HTTP.
  class ConnectionError < Error; end

  # A assinatura de um webhook não confere, está ausente, mal formatada ou
  # fora da tolerância de tempo. Lançada por {FluvPay::Webhooks.verify_signature}.
  class SignatureVerificationError < Error; end

  module Errors
    # Converte uma resposta de erro (status + corpo já parseado) na exceção
    # tipada correspondente. Usado internamente pelo cliente HTTP.
    #
    # @param status_code [Integer] status HTTP da resposta.
    # @param body [Hash, nil] corpo JSON já parseado (espera-se a chave "error").
    # @param retry_after_header [String, nil] valor cru do header Retry-After.
    # @return [FluvPay::Error] a exceção pronta para ser lançada.
    def self.from_response(status_code, body, retry_after_header: nil)
      error_body = body.is_a?(Hash) ? (body["error"] || body[:error]) : nil
      error_body = {} unless error_body.is_a?(Hash)

      code = error_body["code"] || error_body[:code]
      message = error_body["message"] || error_body[:message] || default_message(status_code)
      details = error_body["details"] || error_body[:details] || []
      trace_id = error_body["trace_id"] || error_body[:trace_id]

      kwargs = { code: code, details: details, trace_id: trace_id, status_code: status_code }

      case status_code
      when 400, 422
        ValidationError.new(message, **kwargs)
      when 401
        AuthenticationError.new(message, **kwargs)
      when 403
        PermissionError.new(message, **kwargs)
      when 404
        NotFoundError.new(message, **kwargs)
      when 409
        ConflictError.new(message, **kwargs)
      when 429
        RateLimitError.new(message, retry_after: parse_retry_after(retry_after_header), **kwargs)
      else
        if status_code >= 500
          ServerError.new(message, **kwargs)
        else
          Error.new(message, **kwargs)
        end
      end
    end

    def self.parse_retry_after(raw)
      return nil if raw.nil?

      Float(raw)
    rescue ArgumentError, TypeError
      nil
    end

    def self.default_message(status_code)
      "A FluvPay retornou o status HTTP #{status_code}."
    end

    private_class_method :parse_retry_after, :default_message
  end
end
