# frozen_string_literal: true

module FluvPay
  module Resources
    # Página baseada em +page+/+per_page+ (usada por charges.list e transactions.list).
    #
    # Expõe +#data+ (os itens) e os metadados +page+, +per_page+, +total+,
    # +has_next+ e +has_prev+, exatamente como o backend retorna. Também é
    # iterável: +page.each { |item| ... }+.
    class PageList
      include Enumerable

      # @return [Array<Hash>] itens da página.
      attr_reader :data
      attr_reader :page, :per_page, :total

      def initialize(payload)
        payload ||= {}
        @data = payload["data"] || []
        @page = payload["page"]
        @per_page = payload["per_page"]
        @total = payload["total"]
        @has_next = payload["has_next"]
        @has_prev = payload["has_prev"]
      end

      # @return [Boolean] true se existe próxima página.
      def has_next?
        @has_next ? true : false
      end

      # @return [Boolean] true se existe página anterior.
      def has_prev?
        @has_prev ? true : false
      end

      def each(&block)
        @data.each(&block)
      end
    end

    # Página baseada em +limit+/+offset+ (usada por withdrawals.list e
    # internal_transfers.list). Expõe +#data+ e os metadados +limit+, +offset+
    # e +total+, exatamente como o backend retorna. Também é iterável.
    class OffsetList
      include Enumerable

      # @return [Array<Hash>] itens da página.
      attr_reader :data
      attr_reader :limit, :offset, :total

      def initialize(payload)
        payload ||= {}
        @data = payload["data"] || []
        @limit = payload["limit"]
        @offset = payload["offset"]
        @total = payload["total"]
      end

      def each(&block)
        @data.each(&block)
      end
    end
  end
end
