defmodule Metastatic.Semantic.Domains.Queue do
  @moduledoc """
  Message queue operation patterns for semantic enrichment.

  This module defines patterns for detecting message queue operations across
  multiple languages and queue libraries. Patterns are registered with
  the `Metastatic.Semantic.Patterns` registry at module load time.

  ## Supported Libraries

  ### Elixir
  - **Broadway** - Data processing pipelines
  - **GenStage** - Producer-consumer pipelines
  - **Oban** - Background job processing
  - **Exq** - Redis-backed job processing

  ### Python
  - **Celery** - Distributed task queue
  - **RQ (Redis Queue)** - Simple job queue
  - **Dramatiq** - Background task processing
  - **Kombu** - Messaging library for Python

  ### Ruby
  - **Sidekiq** - Background job processing
  - **Resque** - Redis-backed job processing
  - **Delayed::Job** - Database-backed background jobs
  - **ActiveJob** - Rails job framework

  ### JavaScript
  - **Bull/BullMQ** - Redis-based queue
  - **Agenda** - Job scheduling
  - **Bee-Queue** - Redis job queue
  - **amqplib** - RabbitMQ client

  ## Queue Operations

  | Operation | Description |
  |-----------|-------------|
  | `:publish` | Publish/send message to queue |
  | `:consume` | Consume/receive message from queue |
  | `:subscribe` | Subscribe to queue/topic |
  | `:acknowledge` | Acknowledge message processing |
  | `:reject` | Reject/nack message |
  | `:enqueue` | Add job to queue |
  | `:dequeue` | Remove job from queue |
  | `:schedule` | Schedule delayed job |
  | `:retry` | Retry failed job |
  | `:process` | Process job/message |

  ## Pattern Structure

  Each pattern is a tuple of `{pattern, spec}` where:
  - `pattern` - String or Regex to match function names
  - `spec` - Map with operation details:
    - `:operation` - The queue operation type
    - `:framework` - The queue library identifier
    - `:extract_target` - Strategy for extracting queue/topic name
  """

  alias Metastatic.Semantic.Patterns

  # ----- Elixir/Broadway Patterns -----

  @elixir_broadway_patterns [
    {"Broadway.start_link", %{operation: :consume, framework: :broadway, extract_target: :none}},
    {"Broadway.push_messages",
     %{operation: :publish, framework: :broadway, extract_target: :first_arg}},
    {"Broadway.test_message",
     %{operation: :publish, framework: :broadway, extract_target: :first_arg}},
    {"Broadway.Producer.push_messages",
     %{operation: :publish, framework: :broadway, extract_target: :first_arg}}
  ]

  # ----- Elixir/Oban Patterns -----

  @elixir_oban_patterns [
    {"Oban.insert", %{operation: :enqueue, framework: :oban, extract_target: :first_arg}},
    {"Oban.insert!", %{operation: :enqueue, framework: :oban, extract_target: :first_arg}},
    {"Oban.insert_all", %{operation: :enqueue, framework: :oban, extract_target: :first_arg}},
    {"Oban.insert_all!", %{operation: :enqueue, framework: :oban, extract_target: :first_arg}},
    {"Oban.start_queue", %{operation: :consume, framework: :oban, extract_target: :first_arg}},
    {"Oban.stop_queue", %{operation: :consume, framework: :oban, extract_target: :first_arg}},
    {"Oban.pause_queue", %{operation: :consume, framework: :oban, extract_target: :first_arg}},
    {"Oban.resume_queue", %{operation: :consume, framework: :oban, extract_target: :first_arg}},
    {"Oban.retry_job", %{operation: :retry, framework: :oban, extract_target: :first_arg}},
    {"Oban.retry_all_jobs", %{operation: :retry, framework: :oban, extract_target: :none}},
    {"Oban.cancel_job", %{operation: :reject, framework: :oban, extract_target: :first_arg}},
    {"*.new", %{operation: :enqueue, framework: :oban, extract_target: :none}},
    # Worker perform callback
    {"perform", %{operation: :process, framework: :oban, extract_target: :none}}
  ]

  # ----- Elixir/GenStage Patterns -----

  @elixir_genstage_patterns [
    {"GenStage.start_link", %{operation: :consume, framework: :genstage, extract_target: :none}},
    {"GenStage.sync_subscribe",
     %{operation: :subscribe, framework: :genstage, extract_target: :first_arg}},
    {"GenStage.async_subscribe",
     %{operation: :subscribe, framework: :genstage, extract_target: :first_arg}},
    {"GenStage.demand", %{operation: :consume, framework: :genstage, extract_target: :none}},
    {"GenStage.reply", %{operation: :publish, framework: :genstage, extract_target: :none}}
  ]

  # ----- Elixir/AMQP (RabbitMQ) Patterns -----

  @elixir_amqp_patterns [
    {"AMQP.Basic.publish", %{operation: :publish, framework: :amqp, extract_target: :first_arg}},
    {"AMQP.Basic.consume", %{operation: :consume, framework: :amqp, extract_target: :first_arg}},
    {"AMQP.Basic.ack", %{operation: :acknowledge, framework: :amqp, extract_target: :none}},
    {"AMQP.Basic.nack", %{operation: :reject, framework: :amqp, extract_target: :none}},
    {"AMQP.Basic.reject", %{operation: :reject, framework: :amqp, extract_target: :none}},
    {"AMQP.Basic.get", %{operation: :dequeue, framework: :amqp, extract_target: :first_arg}},
    {"AMQP.Queue.declare",
     %{operation: :subscribe, framework: :amqp, extract_target: :first_arg}},
    {"AMQP.Queue.bind", %{operation: :subscribe, framework: :amqp, extract_target: :first_arg}},
    {"AMQP.Exchange.declare",
     %{operation: :subscribe, framework: :amqp, extract_target: :first_arg}}
  ]

  # ----- Python/Celery Patterns -----

  @python_celery_patterns [
    {"task.delay", %{operation: :enqueue, framework: :celery, extract_target: :receiver}},
    {"task.apply_async", %{operation: :enqueue, framework: :celery, extract_target: :receiver}},
    {"task.apply", %{operation: :enqueue, framework: :celery, extract_target: :receiver}},
    {"celery.send_task", %{operation: :enqueue, framework: :celery, extract_target: :first_arg}},
    {"app.send_task", %{operation: :enqueue, framework: :celery, extract_target: :first_arg}},
    {~r/\.delay$/, %{operation: :enqueue, framework: :celery, extract_target: :receiver}},
    {~r/\.apply_async$/, %{operation: :enqueue, framework: :celery, extract_target: :receiver}},
    {"celery.task", %{operation: :process, framework: :celery, extract_target: :none}},
    {"app.task", %{operation: :process, framework: :celery, extract_target: :none}},
    {"retry", %{operation: :retry, framework: :celery, extract_target: :none}}
  ]

  # ----- Python/RQ Patterns -----

  @python_rq_patterns [
    {"queue.enqueue", %{operation: :enqueue, framework: :rq, extract_target: :first_arg}},
    {"queue.enqueue_at", %{operation: :schedule, framework: :rq, extract_target: :first_arg}},
    {"queue.enqueue_in", %{operation: :schedule, framework: :rq, extract_target: :first_arg}},
    {"Queue.enqueue", %{operation: :enqueue, framework: :rq, extract_target: :first_arg}},
    {"job.get_status", %{operation: :consume, framework: :rq, extract_target: :none}},
    {"job.cancel", %{operation: :reject, framework: :rq, extract_target: :none}},
    {"job.requeue", %{operation: :retry, framework: :rq, extract_target: :none}},
    {"Worker.work", %{operation: :process, framework: :rq, extract_target: :none}}
  ]

  # ----- Python/Kombu Patterns -----

  @python_kombu_patterns [
    {"producer.publish", %{operation: :publish, framework: :kombu, extract_target: :first_arg}},
    {"connection.Producer", %{operation: :publish, framework: :kombu, extract_target: :none}},
    {"connection.Consumer", %{operation: :consume, framework: :kombu, extract_target: :none}},
    {"consumer.consume", %{operation: :consume, framework: :kombu, extract_target: :none}},
    {"message.ack", %{operation: :acknowledge, framework: :kombu, extract_target: :none}},
    {"message.reject", %{operation: :reject, framework: :kombu, extract_target: :none}},
    {"message.requeue", %{operation: :retry, framework: :kombu, extract_target: :none}},
    {"Queue", %{operation: :subscribe, framework: :kombu, extract_target: :first_arg}},
    {"Exchange", %{operation: :subscribe, framework: :kombu, extract_target: :first_arg}}
  ]

  # ----- Ruby/Sidekiq Patterns -----

  @ruby_sidekiq_patterns [
    {"*.perform_async", %{operation: :enqueue, framework: :sidekiq, extract_target: :receiver}},
    {"*.perform_in", %{operation: :schedule, framework: :sidekiq, extract_target: :receiver}},
    {"*.perform_at", %{operation: :schedule, framework: :sidekiq, extract_target: :receiver}},
    {"Sidekiq::Client.push",
     %{operation: :enqueue, framework: :sidekiq, extract_target: :first_arg}},
    {"Sidekiq::Client.push_bulk",
     %{operation: :enqueue, framework: :sidekiq, extract_target: :first_arg}},
    {"perform", %{operation: :process, framework: :sidekiq, extract_target: :none}},
    {"sidekiq_retry_in", %{operation: :retry, framework: :sidekiq, extract_target: :none}}
  ]

  # ----- Ruby/ActiveJob Patterns -----

  @ruby_activejob_patterns [
    {"*.perform_later", %{operation: :enqueue, framework: :activejob, extract_target: :receiver}},
    {"*.perform_now", %{operation: :process, framework: :activejob, extract_target: :receiver}},
    {"*.set", %{operation: :schedule, framework: :activejob, extract_target: :receiver}},
    {"ActiveJob::Base.queue_as",
     %{operation: :subscribe, framework: :activejob, extract_target: :first_arg}},
    {"perform", %{operation: :process, framework: :activejob, extract_target: :none}},
    {"retry_job", %{operation: :retry, framework: :activejob, extract_target: :none}},
    {"discard_on", %{operation: :reject, framework: :activejob, extract_target: :none}}
  ]

  # ----- Ruby/Resque Patterns -----

  @ruby_resque_patterns [
    {"Resque.enqueue", %{operation: :enqueue, framework: :resque, extract_target: :first_arg}},
    {"Resque.enqueue_at",
     %{operation: :schedule, framework: :resque, extract_target: :first_arg}},
    {"Resque.enqueue_in",
     %{operation: :schedule, framework: :resque, extract_target: :first_arg}},
    {"Resque.dequeue", %{operation: :dequeue, framework: :resque, extract_target: :first_arg}},
    {"Resque.reserve", %{operation: :consume, framework: :resque, extract_target: :first_arg}},
    {"perform", %{operation: :process, framework: :resque, extract_target: :none}}
  ]

  # ----- JavaScript/BullMQ Patterns -----

  @javascript_bullmq_patterns [
    {"queue.add", %{operation: :enqueue, framework: :bullmq, extract_target: :first_arg}},
    {"queue.addBulk", %{operation: :enqueue, framework: :bullmq, extract_target: :first_arg}},
    {"queue.getJob", %{operation: :consume, framework: :bullmq, extract_target: :first_arg}},
    {"queue.getJobs", %{operation: :consume, framework: :bullmq, extract_target: :none}},
    {"queue.pause", %{operation: :consume, framework: :bullmq, extract_target: :none}},
    {"queue.resume", %{operation: :consume, framework: :bullmq, extract_target: :none}},
    {"worker.on", %{operation: :subscribe, framework: :bullmq, extract_target: :first_arg}},
    {"Worker", %{operation: :consume, framework: :bullmq, extract_target: :first_arg}},
    {"job.moveToCompleted",
     %{operation: :acknowledge, framework: :bullmq, extract_target: :none}},
    {"job.moveToFailed", %{operation: :reject, framework: :bullmq, extract_target: :none}},
    {"job.retry", %{operation: :retry, framework: :bullmq, extract_target: :none}},
    {"job.remove", %{operation: :dequeue, framework: :bullmq, extract_target: :none}}
  ]

  # ----- JavaScript/amqplib (RabbitMQ) Patterns -----

  @javascript_amqplib_patterns [
    {"channel.publish", %{operation: :publish, framework: :amqplib, extract_target: :first_arg}},
    {"channel.sendToQueue",
     %{operation: :publish, framework: :amqplib, extract_target: :first_arg}},
    {"channel.consume", %{operation: :consume, framework: :amqplib, extract_target: :first_arg}},
    {"channel.ack", %{operation: :acknowledge, framework: :amqplib, extract_target: :none}},
    {"channel.nack", %{operation: :reject, framework: :amqplib, extract_target: :none}},
    {"channel.reject", %{operation: :reject, framework: :amqplib, extract_target: :none}},
    {"channel.assertQueue",
     %{operation: :subscribe, framework: :amqplib, extract_target: :first_arg}},
    {"channel.assertExchange",
     %{operation: :subscribe, framework: :amqplib, extract_target: :first_arg}},
    {"channel.bindQueue",
     %{operation: :subscribe, framework: :amqplib, extract_target: :first_arg}},
    {"channel.get", %{operation: :dequeue, framework: :amqplib, extract_target: :first_arg}}
  ]

  # ----- JavaScript/Agenda Patterns -----

  @javascript_agenda_patterns [
    {"agenda.define", %{operation: :subscribe, framework: :agenda, extract_target: :first_arg}},
    {"agenda.every", %{operation: :schedule, framework: :agenda, extract_target: :first_arg}},
    {"agenda.schedule", %{operation: :schedule, framework: :agenda, extract_target: :first_arg}},
    {"agenda.now", %{operation: :enqueue, framework: :agenda, extract_target: :first_arg}},
    {"agenda.start", %{operation: :consume, framework: :agenda, extract_target: :none}},
    {"agenda.stop", %{operation: :consume, framework: :agenda, extract_target: :none}},
    {"agenda.cancel", %{operation: :reject, framework: :agenda, extract_target: :first_arg}},
    {"job.repeatEvery", %{operation: :schedule, framework: :agenda, extract_target: :first_arg}},
    {"job.schedule", %{operation: :schedule, framework: :agenda, extract_target: :first_arg}},
    {"job.save", %{operation: :enqueue, framework: :agenda, extract_target: :none}}
  ]

  # ----- Registration -----

  @doc """
  Registers all queue patterns for all languages.

  Called automatically when the module is loaded. Can also be called
  manually to re-register patterns (e.g., after clearing).
  """
  @spec register_all() :: :ok
  def register_all do
    # Elixir patterns (Broadway + Oban + GenStage + AMQP)
    Patterns.register(
      :queue,
      :elixir,
      @elixir_broadway_patterns ++
        @elixir_oban_patterns ++ @elixir_genstage_patterns ++ @elixir_amqp_patterns
    )

    # Python patterns (Celery + RQ + Kombu)
    Patterns.register(
      :queue,
      :python,
      @python_celery_patterns ++ @python_rq_patterns ++ @python_kombu_patterns
    )

    # Ruby patterns (Sidekiq + ActiveJob + Resque)
    Patterns.register(
      :queue,
      :ruby,
      @ruby_sidekiq_patterns ++ @ruby_activejob_patterns ++ @ruby_resque_patterns
    )

    # JavaScript patterns (BullMQ + amqplib + Agenda)
    Patterns.register(
      :queue,
      :javascript,
      @javascript_bullmq_patterns ++ @javascript_amqplib_patterns ++ @javascript_agenda_patterns
    )

    :ok
  end

  @doc false
  def __on_definition__(_env, _kind, _name, _args, _guards, _body) do
    :ok
  end
end

# Register patterns when module is loaded
Metastatic.Semantic.Domains.Queue.register_all()
