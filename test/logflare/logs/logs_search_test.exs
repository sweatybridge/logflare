defmodule Logflare.Logs.SearchTest do
  @moduledoc false
  alias Logflare.Sources
  alias Logflare.Logs.Search
  alias Logflare.Logs.Search.{SearchOpts, SearchResult}
  alias Logflare.Google.BigQuery
  alias Logflare.Google.BigQuery.GenUtils
  alias Logflare.Source.BigQuery.Pipeline
  use Logflare.DataCase
  import Logflare.DummyFactory
  alias GoogleApi.BigQuery.V2.Api

  setup do
    u = insert(:user, email: System.get_env("LOGFLARE_TEST_USER_WITH_SET_IAM"))
    s = insert(:source, user_id: u.id)
    s = Sources.get_by(id: s.id)
    {:ok, sources: [s], users: [u]}
  end

  describe "Search" do
    @describetag :skip
    test "search for source and regex", %{sources: [source | _], users: [user | _]} do
      les =
        for x <- 1..5, y <- 100..101 do
          build(:log_event, message: "x#{x} y#{y}", source: source)
        end

      bq_rows = Enum.map(les, &Pipeline.le_to_bq_row/1)
      project_id = GenUtils.get_project_id(source.token)

      assert {:ok, _} = BigQuery.create_dataset("#{user.id}", project_id)
      assert {:ok, _} = BigQuery.create_table(source.token)
      assert {:ok, _} = BigQuery.stream_batch!(source.token, bq_rows)

      {:ok, %{rows: rows}} = Search.search(%SearchOpts{source: source, searchq: ~S|\d\d1|})

      assert length(rows) == 5
    end

    test "search for source and datetime", %{sources: [source | _], users: [user | _]} do
      bq_table_id = System.get_env("LOGFLARE_DEV_BQ_TABLE_ID_FOR_TESTING")
      source = %{source | bq_table_id: bq_table_id}

      partitions = {~N[2019-06-24T00:00:00], ~N[2019-06-24T00:00:00]}

      opts = %SearchOpts{
        source: source,
        partitions: partitions
      }

      {:ok, %{rows: rows}} = Search.search(opts)
      assert length(rows) == 5

      partitions = {~N[2019-06-25T00:00:00], ~N[2019-06-25T00:00:00]}
      opts = %SearchOpts{opts | partitions: partitions}
      {:ok, %{rows: rows}} = Search.search(opts)

      assert length(rows) == 2557

      partitions = {~N[2019-06-26T00:00:00], ~N[2019-06-26T00:00:00]}
      opts = %{opts | partitions: partitions}
      {:ok, %{rows: rows}} = Search.search(opts)

      assert length(rows) == 1899

      partitions = {~N[2019-06-27T00:00:00], ~N[2019-06-27T00:00:00]}
      opts = %{opts | partitions: partitions}
      {:ok, %{rows: rows}} = Search.search(opts)

      assert is_nil(rows)

      partitions = {~N[2019-06-24T00:00:00], ~N[2019-06-27T00:00:00]}
      opts = %{opts | partitions: partitions}
      {:ok, %{rows: rows}} = Search.search(opts)

      assert length(rows) === 4461
    end
  end

  describe "Structured search" do
    test "case 1", %{sources: [source | _], users: [user | _]} do
      bq_table_id = System.get_env("LOGFLARE_DEV_BQ_TABLE_ID_FOR_TESTING")
      source = %{source | bq_table_id: bq_table_id}
      searchq = ~S|
         "this is another" log message
         metadata.request_method:POST
         metadata.custom_user_data.address.st:NY
         metadata.custom_user_data.id:38
         metadata.custom_user_data.login_count:>150
       |

      {:ok, result} =
        Search.search(%SearchOpts{
          searchq: searchq,
          source: source,
          partitions: {Date.utc_today(), Date.utc_today()}
        })

      assert length(result.rows) == 1089
    end
  end

  describe "Query builder" do
    @tag :skip
    test "succeeds for basic query", %{sources: [source | _]} do
      assert Search.to_sql(%SearchOpts{source: source, searchq: ~S|\d\d|}) ==
               {
                 ~s|SELECT t0.timestamp, t0.event_message FROM #{source.bq_table_id} AS t0 WHERE (REGEXP_CONTAINS(t0.event_message, ?))|,
                 ["\\d\\d"]
               }
    end

    @tag :skip
    test "converts Ecto PG sql to BQ sql" do
      ecto_pg_sql =
        "SELECT t0.\"timestamp\", t0.\"event_message\" FROM \"`logflare-dev-238720`.96465_test.4114dde8_1fa0_4efa_93b1_0fe6e4021f3c\" AS t0 WHERE (REGEXP_CONTAINS(t0.\"event_message\", $1))"

      bq_sql =
        "SELECT t0.timestamp, t0.event_message FROM `logflare-dev-238720`.96465_test.4114dde8_1fa0_4efa_93b1_0fe6e4021f3c AS t0 WHERE (REGEXP_CONTAINS(t0.event_message, ?))"

      assert Search.ecto_pg_sql_to_bq_sql(ecto_pg_sql) == bq_sql
    end
  end
end