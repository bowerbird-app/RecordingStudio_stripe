# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require_relative "simplecov_helper"
require "minitest/autorun"
require "rails"
require "active_support/time"
Time.zone ||= "UTC"
require "recording_studio_stripe"

# Cloud Agent secrets must not leak into gem unit tests.
%w[
  STRIPE_SECRET_KEY
  STRIPE_PUBLISHABLE_KEY
  STRIPE_WEBHOOK_SECRET
  Stripe_secret_key
  Stripe_publishable_key
  Stripe_webhook_secret
].each { |name| ENV.delete(name) }
