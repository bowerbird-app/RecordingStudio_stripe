# frozen_string_literal: true

module RecordingStudioStripe
  # Class strings for plan density. Tailwind scans these literals. Do not build a
  # class by interpolating pieces. An unprefixed size that must lose from md is
  # paired with an md: utility marked !. Otherwise stylesheet order can keep the
  # phone size on the desktop card.
  #
  # The feature list is the next sibling of details, not a child. A closed
  # details element hides its children, so the list would vanish inside it from
  # md. FlatPack::Collapse sets hidden on connect, and preflight turns [hidden]
  # into display:none !important, so one Collapse cannot be a closed phone
  # disclosure and a visible subgrid row.
  module PlanCardDensity
    SUMMARY = %w[
      flex cursor-pointer list-none items-center gap-1 py-1
      text-[length:var(--text-sm)] font-medium
      text-[var(--surface-muted-content-color)]
      [&::-webkit-details-marker]:hidden
    ].join(" ").freeze

    CHEVRON = "shrink-0 transition-transform group-open:rotate-180"

    def self.slot(density, name)
      TABLE.fetch(density).fetch(name)
    end

    AUTO_SHELL = "h-full md:grid md:row-span-4 md:grid-rows-subgrid"
    AUTO_CARD = "h-full md:[display:grid]! md:[grid-template-rows:subgrid]! md:[grid-row:span_4]!"
    AUTO_BODY = %w{
      grid
      max-md:grid-cols-[minmax(0,1fr)_auto]
      max-md:items-center
      max-md:gap-x-3
      max-md:gap-y-1
      p-[var(--card-padding-sm)]
      md:grid-cols-1
      md:row-span-4
      md:grid-rows-subgrid
      md:items-stretch
      md:gap-0
      md:p-[var(--card-padding-md)]!
    }.join(" ").freeze
    AUTO_TITLE = "min-w-0 max-md:col-start-1 max-md:row-start-1"
    AUTO_NAME = %w{
      m-0
      font-bold
      leading-tight
      fp-text-balance
      text-[var(--surface-content-color)]
      text-[length:var(--text-base)]
      max-md:overflow-hidden!
      max-md:text-ellipsis!
      max-md:whitespace-nowrap!
      md:text-[length:var(--page-title-h3-size)]!
    }.join(" ").freeze
    AUTO_SUBTITLE = "m-0 mt-2 text-lg fp-text-pretty text-[var(--surface-muted-content-color)]"
    AUTO_SUBTITLE_QUIET = "m-0 mt-2 text-lg fp-text-pretty text-[var(--surface-muted-content-color)] max-md:hidden"
    AUTO_PRICE = %w[
      min-w-0
      max-md:col-start-1
      max-md:row-start-2
      flex
      max-md:flex-row
      max-md:flex-wrap
      max-md:items-baseline
      max-md:gap-x-2
      max-md:gap-y-0.5
      md:h-full
      md:flex-col
      md:items-start
      md:justify-end
      md:gap-2
    ].join(" ").freeze
    AUTO_AMOUNT = "leading-none text-[length:var(--text-xl)] md:text-[length:var(--page-title-h2-size)]!"
    AUTO_UNIT = "leading-none text-[length:var(--text-sm)] md:text-[length:var(--text-lg)]!"
    AUTO_ACTION = %w[
      max-md:col-start-2
      max-md:row-start-1
      max-md:row-span-2
      max-md:w-auto
      max-md:shrink-0
      max-md:self-center
      max-md:justify-self-end
      md:flex
      md:w-full
      md:flex-col
      md:justify-start
    ].join(" ").freeze
    AUTO_FORM = "m-0 flex flex-col max-md:w-auto md:w-full"
    AUTO_CONTROL = "max-md:w-auto md:w-full"
    AUTO_INCLUSIONS = "min-w-0 max-md:col-span-2 max-md:col-start-1 max-md:row-start-3"
    AUTO_DISCLOSURE = "peer group m-0 md:hidden"
    AUTO_LIST_FRAME = "max-md:hidden peer-open:block! md:block"

    ROWS_SHELL = "min-w-0 w-full"
    ROWS_CARD = "h-full"
    ROWS_BODY = %w{
      grid
      grid-cols-[minmax(0,1fr)_auto]
      items-center
      gap-x-3
      gap-y-1
      p-[var(--card-padding-sm)]
    }.join(" ").freeze
    ROWS_TITLE = "min-w-0 col-start-1 row-start-1"
    ROWS_NAME = %w{
      m-0
      font-bold
      leading-tight
      fp-text-balance
      text-[var(--surface-content-color)]
      text-[length:var(--text-base)]
      overflow-hidden!
      text-ellipsis!
      whitespace-nowrap!
    }.join(" ").freeze
    ROWS_SUBTITLE = "m-0 mt-2 text-lg fp-text-pretty text-[var(--surface-muted-content-color)]"
    ROWS_SUBTITLE_QUIET = "m-0 mt-2 text-lg fp-text-pretty text-[var(--surface-muted-content-color)] hidden"
    ROWS_PRICE = "min-w-0 col-start-1 row-start-2 flex flex-row flex-wrap items-baseline gap-x-2 gap-y-0.5"
    ROWS_AMOUNT = "leading-none text-[length:var(--text-xl)]"
    ROWS_UNIT = "leading-none text-[length:var(--text-sm)]"
    ROWS_ACTION = "col-start-2 row-start-1 row-span-2 w-auto shrink-0 self-center justify-self-end"
    ROWS_FORM = "m-0 flex w-auto flex-col"
    ROWS_CONTROL = "w-auto"
    ROWS_INCLUSIONS = "min-w-0 col-span-2 col-start-1 row-start-3"
    ROWS_DISCLOSURE = "peer group m-0"
    ROWS_LIST_FRAME = "hidden peer-open:block!"

    TABLE = {
      auto: {
        shell: AUTO_SHELL,
        card: AUTO_CARD,
        body: AUTO_BODY,
        title: AUTO_TITLE,
        name: AUTO_NAME,
        subtitle: AUTO_SUBTITLE,
        subtitle_quiet: AUTO_SUBTITLE_QUIET,
        price: AUTO_PRICE,
        amount: AUTO_AMOUNT,
        unit: AUTO_UNIT,
        action: AUTO_ACTION,
        form: AUTO_FORM,
        button: AUTO_CONTROL,
        inclusions: AUTO_INCLUSIONS,
        disclosure: AUTO_DISCLOSURE,
        list_frame: AUTO_LIST_FRAME
      }.freeze,
      rows: {
        shell: ROWS_SHELL,
        card: ROWS_CARD,
        body: ROWS_BODY,
        title: ROWS_TITLE,
        name: ROWS_NAME,
        subtitle: ROWS_SUBTITLE,
        subtitle_quiet: ROWS_SUBTITLE_QUIET,
        price: ROWS_PRICE,
        amount: ROWS_AMOUNT,
        unit: ROWS_UNIT,
        action: ROWS_ACTION,
        form: ROWS_FORM,
        button: ROWS_CONTROL,
        inclusions: ROWS_INCLUSIONS,
        disclosure: ROWS_DISCLOSURE,
        list_frame: ROWS_LIST_FRAME
      }.freeze
    }.freeze
    private_constant :TABLE
  end
end
