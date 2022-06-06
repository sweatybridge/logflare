defmodule Logflare.Billing do
  @moduledoc false
  require Logger
  alias __MODULE__
  import Ecto.Query, warn: false
  alias Logflare.{Repo, Users, Source, User, Billing.BillingAccount}
  require Protocol
  Protocol.derive(Jason.Encoder, Stripe.List)
  Protocol.derive(Jason.Encoder, Stripe.Subscription)
  Protocol.derive(Jason.Encoder, Stripe.Plan)
  Protocol.derive(Jason.Encoder, Stripe.SubscriptionItem)
  Protocol.derive(Jason.Encoder, Stripe.Session)
  Protocol.derive(Jason.Encoder, Stripe.Invoice)
  Protocol.derive(Jason.Encoder, Stripe.LineItem)
  Protocol.derive(Jason.Encoder, Stripe.Price)
  Protocol.derive(Jason.Encoder, Stripe.Discount)
  Protocol.derive(Jason.Encoder, Stripe.Coupon)

  @doc "Returns the list of billing_accounts"
  @spec list_billing_accounts() :: [%BillingAccount{}]
  def list_billing_accounts, do: Repo.all(BillingAccount)

  @doc "Gets a single billing_account by a keyword."
  @spec get_billing_account_by(keyword()) :: %BillingAccount{} | nil
  def get_billing_account_by(kv), do: Repo.get_by(BillingAccount, kv)

  @doc "Gets a single billing_account. Raises `Ecto.NoResultsError` if the Billing account does not exist."
  @spec get_billing_account!(String.t() | number()) :: %BillingAccount{}
  def get_billing_account!(id), do: Repo.get!(BillingAccount, id)

  @doc "Creates a billing_account."
  @spec create_billing_account(%User{}, map()) ::
          {:ok, %BillingAccount{}} | {:error, %Ecto.Changeset{}}
  def create_billing_account(%User{} = user, attrs \\ %{}) do
    user
    |> Ecto.build_assoc(:billing_account)
    |> BillingAccount.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, _user} = res ->
        # move this to be the default on user create after launch
        Users.update_user_all_fields(user, %{billing_enabled: true})

        Source.Supervisor.reset_all_user_sources(user)
        res

      {:error, _changeset = res} ->
        res
    end
  end

  @doc "Syncs stripe subscription with %BillingAccount{} with Stripe as source of truth."
  @spec sync_subscriptions(nil | %BillingAccount{}) ::
          :noop | {:ok, %BillingAccount{}} | {:error, %Ecto.Changeset{}}
  def sync_subscriptions(nil), do: :noop

  def sync_subscriptions(%BillingAccount{stripe_customer: stripe_customer_id} = billing_account) do
    with {:ok, subscriptions} <-
           Billing.Stripe.list_customer_subscriptions(stripe_customer_id) do
      update_billing_account(billing_account, %{stripe_subscriptions: subscriptions})
    end
  end

  @doc "Syncs stripe invoices with %BillingAccount{} with Stripe as source of truth."
  @spec sync_invoices(nil | %BillingAccount{}) ::
          :noop | {:ok, %BillingAccount{}} | {:error, %Ecto.Changeset{}}
  def sync_invoices(nil), do: :noop

  def sync_invoices(%BillingAccount{stripe_customer: stripe_customer_id} = billing_account) do
    with {:ok, invoices} <- Billing.Stripe.list_customer_invoices(stripe_customer_id) do
      attrs = %{stripe_invoices: invoices}

      update_billing_account(billing_account, attrs)
    else
      err -> err
    end
  end

  @doc "Syncs stripe data with %BillingAccount{} with Stripe as source of truth."
  @spec sync_billing_account(nil | %BillingAccount{}) ::
          :noop | {:ok, %BillingAccount{}} | {:error, %Ecto.Changeset{}}
  def sync_billing_account(
        %BillingAccount{stripe_customer: customer_id} = billing_account,
        attrs \\ %{}
      ) do
    with {:ok, subscriptions} <- Billing.Stripe.list_customer_subscriptions(customer_id),
         {:ok, invoices} <- Billing.Stripe.list_customer_invoices(customer_id),
         {:ok, customer} <- Billing.Stripe.retrieve_customer(customer_id) do
      attrs =
        attrs
        |> Map.put(:stripe_subscriptions, subscriptions)
        |> Map.put(:stripe_invoices, invoices)
        |> Map.put(:default_payment_method, customer.invoice_settings.default_payment_method)
        |> Map.put(:custom_invoice_fields, customer.invoice_settings.custom_fields)

      update_billing_account(billing_account, attrs)
    end
  end

  @doc "Updates a billing_account"
  @spec update_billing_account(%BillingAccount{}, map()) ::
          {:ok, %BillingAccount{}} | {:error, %Ecto.Changeset{}}
  def update_billing_account(%BillingAccount{} = billing_account, attrs) do
    billing_account
    |> BillingAccount.changeset(attrs)
    |> Repo.update()
  end

  @doc "Preloads the payment methods field"
  @spec preload_payment_methods(%BillingAccount{}) :: %BillingAccount{}
  def preload_payment_methods(ba), do: Repo.preload(ba, :payment_methods)

  @doc "Deletes a BillingAccount for a User"
  @spec delete_billing_account(%User{}) :: {:ok, %BillingAccount{}} | {:error, %Ecto.Changeset{}}
  def delete_billing_account(%User{billing_account: billing_account} = user) do
    with {:ok, _} = res <- Repo.delete(billing_account) do
      Source.Supervisor.reset_all_user_sources(user)
      res
    end
  end

  @doc "Returns an `%Ecto.Changeset{}` for tracking billing_account changes."
  @spec change_billing_account(%BillingAccount{}) :: %Ecto.Changeset{}
  def change_billing_account(%BillingAccount{} = billing_account) do
    BillingAccount.changeset(billing_account, %{})
  end

  @doc "retrieves the stripe plan stored on the BillingAccount"
  @spec get_billing_account_stripe_plan(%BillingAccount{}) :: nil | term()
  def get_billing_account_stripe_plan(%BillingAccount{
        stripe_subscriptions: %{"data" => [%{"plan" => plan} | _]}
      }),
      do: plan

  def get_billing_account_stripe_plan(_), do: nil

  @doc "gets the stripe subscription item data stored on the BillingAccount"
  @spec get_billing_account_stripe_subscription_item(%BillingAccount{}) :: nil | term()

  def get_billing_account_stripe_subscription_item(%BillingAccount{
        stripe_subscriptions: %{
          "data" => [%{"items" => [%{"data" => [item | _]} | _]} | _]
        }
      }),
      do: item

  def get_billing_account_stripe_subscription_item(_), do: nil
end