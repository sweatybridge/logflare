ExUnit.start()
Faker.start()
alias Logflare.{Lql, Billing, Logs, Sources}

# Mimick mocks setup
Mimic.copy(Logs.LogEvents)
Mimic.copy(Logs.SearchQueryExecutor)
Mimic.copy(Lql)
Mimic.copy(Billing)
Mimic.copy(Sources.Counters)
Mimic.copy(Sources.Cache)
Mimic.copy(Stripe.PaymentMethod)

{:ok, _} = Application.ensure_all_started(:ex_machina)
{:ok, _} = Application.ensure_all_started(:mimic)

ExUnit.configure(exclude: [integration: true, failing: true])

Ecto.Adapters.SQL.Sandbox.mode(Logflare.Repo, :manual)
