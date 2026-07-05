defmodule Metastatic.Semantic.Domains.ExternalApi do
  @moduledoc """
  External API operation patterns for semantic enrichment.

  This module defines patterns for detecting external/third-party API calls across
  multiple languages. These are higher-level service integrations beyond basic HTTP.
  Patterns are registered with the `Metastatic.Semantic.Patterns` registry at module load time.

  ## Supported Services

  ### Cloud Services
  - **AWS SDK** - Amazon Web Services
  - **Google Cloud** - GCP services
  - **Azure** - Microsoft Azure
  - **Stripe** - Payment processing
  - **Twilio** - Communication APIs
  - **SendGrid** - Email services

  ### Social/OAuth
  - **GitHub API** - GitHub integrations
  - **Slack API** - Slack integrations
  - **Twitter/X API** - Social media

  ## External API Operations

  | Operation | Description |
  |-----------|-------------|
  | `:call` | Generic API call |
  | `:upload` | Upload to external service |
  | `:download` | Download from external service |
  | `:send` | Send notification/message |
  | `:charge` | Payment/billing operation |
  | `:webhook` | Webhook handling |
  | `:search` | Search/query external service |
  | `:sync` | Synchronization with service |

  ## Pattern Structure

  Each pattern is a tuple of `{pattern, spec}` where:
  - `pattern` - String or Regex to match function names
  - `spec` - Map with operation details:
    - `:operation` - The external API operation type
    - `:framework` - The service/SDK identifier
    - `:extract_target` - Strategy for extracting service/resource name
  """

  alias Metastatic.Semantic.Patterns

  defmodule R do
    @moduledoc false

    # ----- AWS SDK Patterns (Elixir - ex_aws) -----

    def elixir_aws_patterns,
      do: [
        {"ExAws.request", %{operation: :call, framework: :ex_aws, extract_target: :first_arg}},
        {"ExAws.request!", %{operation: :call, framework: :ex_aws, extract_target: :first_arg}},
        {"ExAws.S3.put_object",
         %{operation: :upload, framework: :ex_aws, extract_target: :first_arg}},
        {"ExAws.S3.get_object",
         %{operation: :download, framework: :ex_aws, extract_target: :first_arg}},
        {"ExAws.S3.delete_object",
         %{operation: :call, framework: :ex_aws, extract_target: :first_arg}},
        {"ExAws.S3.list_objects",
         %{operation: :search, framework: :ex_aws, extract_target: :first_arg}},
        {"ExAws.SES.send_email", %{operation: :send, framework: :ex_aws, extract_target: :none}},
        {"ExAws.SNS.publish",
         %{operation: :send, framework: :ex_aws, extract_target: :first_arg}},
        {"ExAws.SQS.send_message",
         %{operation: :send, framework: :ex_aws, extract_target: :first_arg}},
        {"ExAws.Lambda.invoke",
         %{operation: :call, framework: :ex_aws, extract_target: :first_arg}}
      ]

    # ----- Stripe Patterns (Elixir - stripity_stripe) -----

    def elixir_stripe_patterns,
      do: [
        {"Stripe.Charge.create",
         %{operation: :charge, framework: :stripe, extract_target: :none}},
        {"Stripe.PaymentIntent.create",
         %{operation: :charge, framework: :stripe, extract_target: :none}},
        {"Stripe.PaymentIntent.confirm",
         %{operation: :charge, framework: :stripe, extract_target: :first_arg}},
        {"Stripe.Customer.create",
         %{operation: :call, framework: :stripe, extract_target: :none}},
        {"Stripe.Customer.retrieve",
         %{operation: :call, framework: :stripe, extract_target: :first_arg}},
        {"Stripe.Subscription.create",
         %{operation: :charge, framework: :stripe, extract_target: :none}},
        {"Stripe.Refund.create",
         %{operation: :charge, framework: :stripe, extract_target: :none}},
        {"Stripe.Webhook.construct_event",
         %{operation: :webhook, framework: :stripe, extract_target: :none}}
      ]

    # ----- Twilio Patterns (Elixir - ex_twilio) -----

    def elixir_twilio_patterns,
      do: [
        {"ExTwilio.Message.create",
         %{operation: :send, framework: :twilio, extract_target: :none}},
        {"ExTwilio.Call.create", %{operation: :send, framework: :twilio, extract_target: :none}},
        {"ExTwilio.Message.find",
         %{operation: :call, framework: :twilio, extract_target: :first_arg}}
      ]

    # ----- Python/AWS boto3 Patterns -----

    def python_aws_patterns,
      do: [
        {"client.put_object", %{operation: :upload, framework: :boto3, extract_target: :none}},
        {"client.get_object", %{operation: :download, framework: :boto3, extract_target: :none}},
        {"client.delete_object", %{operation: :call, framework: :boto3, extract_target: :none}},
        {"client.list_objects", %{operation: :search, framework: :boto3, extract_target: :none}},
        {"client.send_email", %{operation: :send, framework: :boto3, extract_target: :none}},
        {"client.publish", %{operation: :send, framework: :boto3, extract_target: :none}},
        {"client.send_message", %{operation: :send, framework: :boto3, extract_target: :none}},
        {"client.invoke", %{operation: :call, framework: :boto3, extract_target: :first_arg}},
        {"s3.upload_file", %{operation: :upload, framework: :boto3, extract_target: :first_arg}},
        {"s3.download_file",
         %{operation: :download, framework: :boto3, extract_target: :first_arg}},
        {"s3.upload_fileobj", %{operation: :upload, framework: :boto3, extract_target: :none}},
        {"s3.download_fileobj",
         %{operation: :download, framework: :boto3, extract_target: :none}},
        {"boto3.client", %{operation: :call, framework: :boto3, extract_target: :first_arg}},
        {"boto3.resource", %{operation: :call, framework: :boto3, extract_target: :first_arg}}
      ]

    # ----- Python/Stripe Patterns -----

    def python_stripe_patterns,
      do: [
        {"stripe.Charge.create",
         %{operation: :charge, framework: :stripe, extract_target: :none}},
        {"stripe.PaymentIntent.create",
         %{operation: :charge, framework: :stripe, extract_target: :none}},
        {"stripe.PaymentIntent.confirm",
         %{operation: :charge, framework: :stripe, extract_target: :none}},
        {"stripe.Customer.create",
         %{operation: :call, framework: :stripe, extract_target: :none}},
        {"stripe.Customer.retrieve",
         %{operation: :call, framework: :stripe, extract_target: :first_arg}},
        {"stripe.Subscription.create",
         %{operation: :charge, framework: :stripe, extract_target: :none}},
        {"stripe.Refund.create",
         %{operation: :charge, framework: :stripe, extract_target: :none}},
        {"stripe.Webhook.construct_event",
         %{operation: :webhook, framework: :stripe, extract_target: :none}}
      ]

    # ----- Python/Twilio Patterns -----

    def python_twilio_patterns,
      do: [
        {"client.messages.create",
         %{operation: :send, framework: :twilio, extract_target: :none}},
        {"client.calls.create", %{operation: :send, framework: :twilio, extract_target: :none}},
        {"twilio.rest.Client", %{operation: :call, framework: :twilio, extract_target: :none}}
      ]

    # ----- Python/SendGrid Patterns -----

    def python_sendgrid_patterns,
      do: [
        {"sendgrid.send", %{operation: :send, framework: :sendgrid, extract_target: :first_arg}},
        {"sg.send", %{operation: :send, framework: :sendgrid, extract_target: :first_arg}},
        {"Mail", %{operation: :send, framework: :sendgrid, extract_target: :none}}
      ]

    # ----- Ruby/AWS SDK Patterns -----

    def ruby_aws_patterns,
      do: [
        {"client.put_object", %{operation: :upload, framework: :aws_sdk, extract_target: :none}},
        {"client.get_object",
         %{operation: :download, framework: :aws_sdk, extract_target: :none}},
        {"client.delete_object", %{operation: :call, framework: :aws_sdk, extract_target: :none}},
        {"client.list_objects",
         %{operation: :search, framework: :aws_sdk, extract_target: :none}},
        {"s3.put_object", %{operation: :upload, framework: :aws_sdk, extract_target: :none}},
        {"s3.get_object", %{operation: :download, framework: :aws_sdk, extract_target: :none}},
        {"Aws::S3::Client.new", %{operation: :call, framework: :aws_sdk, extract_target: :none}},
        {"Aws::S3::Resource.new", %{operation: :call, framework: :aws_sdk, extract_target: :none}}
      ]

    # ----- Ruby/Stripe Patterns -----

    def ruby_stripe_patterns,
      do: [
        {"Stripe::Charge.create",
         %{operation: :charge, framework: :stripe, extract_target: :none}},
        {"Stripe::PaymentIntent.create",
         %{operation: :charge, framework: :stripe, extract_target: :none}},
        {"Stripe::PaymentIntent.confirm",
         %{operation: :charge, framework: :stripe, extract_target: :none}},
        {"Stripe::Customer.create",
         %{operation: :call, framework: :stripe, extract_target: :none}},
        {"Stripe::Customer.retrieve",
         %{operation: :call, framework: :stripe, extract_target: :first_arg}},
        {"Stripe::Subscription.create",
         %{operation: :charge, framework: :stripe, extract_target: :none}},
        {"Stripe::Refund.create",
         %{operation: :charge, framework: :stripe, extract_target: :none}},
        {"Stripe::Webhook.construct_event",
         %{operation: :webhook, framework: :stripe, extract_target: :none}}
      ]

    # ----- Ruby/Twilio Patterns -----

    def ruby_twilio_patterns,
      do: [
        {"client.messages.create",
         %{operation: :send, framework: :twilio, extract_target: :none}},
        {"client.calls.create", %{operation: :send, framework: :twilio, extract_target: :none}},
        {"Twilio::REST::Client.new",
         %{operation: :call, framework: :twilio, extract_target: :none}}
      ]

    # ----- JavaScript/AWS SDK Patterns -----

    def javascript_aws_patterns,
      do: [
        {"s3.putObject", %{operation: :upload, framework: :aws_sdk_js, extract_target: :none}},
        {"s3.getObject", %{operation: :download, framework: :aws_sdk_js, extract_target: :none}},
        {"s3.deleteObject", %{operation: :call, framework: :aws_sdk_js, extract_target: :none}},
        {"s3.listObjects", %{operation: :search, framework: :aws_sdk_js, extract_target: :none}},
        {"s3.upload", %{operation: :upload, framework: :aws_sdk_js, extract_target: :none}},
        {"ses.sendEmail", %{operation: :send, framework: :aws_sdk_js, extract_target: :none}},
        {"sns.publish", %{operation: :send, framework: :aws_sdk_js, extract_target: :none}},
        {"sqs.sendMessage", %{operation: :send, framework: :aws_sdk_js, extract_target: :none}},
        {"lambda.invoke", %{operation: :call, framework: :aws_sdk_js, extract_target: :none}},
        # AWS SDK v3 patterns
        {"client.send", %{operation: :call, framework: :aws_sdk_js, extract_target: :first_arg}},
        {"S3Client", %{operation: :call, framework: :aws_sdk_js, extract_target: :none}},
        {"PutObjectCommand",
         %{operation: :upload, framework: :aws_sdk_js, extract_target: :none}},
        {"GetObjectCommand",
         %{operation: :download, framework: :aws_sdk_js, extract_target: :none}}
      ]

    # ----- JavaScript/Stripe Patterns -----

    def javascript_stripe_patterns,
      do: [
        {"stripe.charges.create",
         %{operation: :charge, framework: :stripe, extract_target: :none}},
        {"stripe.paymentIntents.create",
         %{operation: :charge, framework: :stripe, extract_target: :none}},
        {"stripe.paymentIntents.confirm",
         %{operation: :charge, framework: :stripe, extract_target: :none}},
        {"stripe.customers.create",
         %{operation: :call, framework: :stripe, extract_target: :none}},
        {"stripe.customers.retrieve",
         %{operation: :call, framework: :stripe, extract_target: :first_arg}},
        {"stripe.subscriptions.create",
         %{operation: :charge, framework: :stripe, extract_target: :none}},
        {"stripe.refunds.create",
         %{operation: :charge, framework: :stripe, extract_target: :none}},
        {"stripe.webhooks.constructEvent",
         %{operation: :webhook, framework: :stripe, extract_target: :none}}
      ]

    # ----- JavaScript/Twilio Patterns -----

    def javascript_twilio_patterns,
      do: [
        {"client.messages.create",
         %{operation: :send, framework: :twilio, extract_target: :none}},
        {"client.calls.create", %{operation: :send, framework: :twilio, extract_target: :none}},
        {"twilio", %{operation: :call, framework: :twilio, extract_target: :none}}
      ]

    # ----- JavaScript/SendGrid Patterns -----

    def javascript_sendgrid_patterns,
      do: [
        {"sgMail.send", %{operation: :send, framework: :sendgrid, extract_target: :first_arg}},
        {"sgMail.sendMultiple",
         %{operation: :send, framework: :sendgrid, extract_target: :first_arg}},
        {"client.send", %{operation: :send, framework: :sendgrid, extract_target: :first_arg}}
      ]
  end

  # ----- Registration -----

  @doc """
  Registers all external API patterns for all languages.

  Called automatically when the module is loaded. Can also be called
  manually to re-register patterns (e.g., after clearing).
  """
  @spec register_all() :: :ok
  def register_all do
    # Elixir patterns (ExAws + Stripe + Twilio)
    Patterns.register(
      :external_api,
      :elixir,
      R.elixir_aws_patterns() ++ R.elixir_stripe_patterns() ++ R.elixir_twilio_patterns()
    )

    # Python patterns (boto3 + Stripe + Twilio + SendGrid)
    Patterns.register(
      :external_api,
      :python,
      R.python_aws_patterns() ++
        R.python_stripe_patterns() ++
        R.python_twilio_patterns() ++ R.python_sendgrid_patterns()
    )

    # Ruby patterns (AWS SDK + Stripe + Twilio)
    Patterns.register(
      :external_api,
      :ruby,
      R.ruby_aws_patterns() ++ R.ruby_stripe_patterns() ++ R.ruby_twilio_patterns()
    )

    # JavaScript patterns (AWS SDK + Stripe + Twilio + SendGrid)
    Patterns.register(
      :external_api,
      :javascript,
      R.javascript_aws_patterns() ++
        R.javascript_stripe_patterns() ++
        R.javascript_twilio_patterns() ++ R.javascript_sendgrid_patterns()
    )

    :ok
  end

  @doc false
  def __on_definition__(_env, _kind, _name, _args, _guards, _body) do
    :ok
  end
end

# Register patterns when module is loaded
Metastatic.Semantic.Domains.ExternalApi.register_all()
