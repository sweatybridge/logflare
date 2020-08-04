defmodule Logflare.Plans.Plan do
  use Ecto.Schema
  import Ecto.Changeset

  schema "plans" do
    field :name, :string
    field :stripe_id, :string
    field :price, :integer
    field :period, :string
    field :limit_sources, :integer
    field :limit_rate_limit, :integer
    field :limit_source_rate_limit, :integer
    field :limit_alert_freq, :integer
    field :limit_saved_search_limit, :integer
    field :limit_team_users_limit, :integer
    field :limit_source_fields_limit, :integer

    timestamps()
  end

  @doc false
  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [
      :name,
      :stripe_id,
      :price,
      :period,
      :limit_sources,
      :limit_rate_limit,
      :limit_source_rate_limit,
      :limit_alert_freq,
      :limit_saved_search_limit,
      :limit_team_users_limit,
      :limit_source_fields_limit
    ])
    |> validate_required([
      :name,
      :price,
      :period,
      :limit_sources,
      :limit_rate_limit,
      :limit_source_rate_limit,
      :limit_alert_freq,
      :limit_saved_search_limit,
      :limit_team_users_limit,
      :limit_source_fields_limit
    ])
  end
end
