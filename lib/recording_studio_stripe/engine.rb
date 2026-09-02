# frozen_string_literal: true

module RecordingStudioStripe
  class Engine < ::Rails::Engine
    isolate_namespace RecordingStudioStripe

    class << self
      def apply_model_extensions(target)
        apply_extensions(target, extensions_for(:model, extension_keys_for(target)))
      end

      def apply_controller_extensions(target)
        apply_extensions(target, extensions_for(:controller, extension_keys_for(target)))
      end

      private

      def extensions_for(kind, names)
        hooks = RecordingStudioStripe.configuration.hooks
        Array(names).flat_map do |name|
          if kind == :model
            hooks.model_extensions_for(name)
          else
            hooks.controller_extensions_for(name)
          end
        end
      end

      def apply_extensions(target, extensions)
        return unless target

        applied = target.instance_variable_get(:@recording_studio_stripe_applied_extensions) || identity_hash

        extensions.flatten.compact.each do |extension|
          next if applied[extension]

          target.class_eval(&extension)
          applied[extension] = true
        end

        target.instance_variable_set(:@recording_studio_stripe_applied_extensions, applied)
      end

      def extension_keys_for(target)
        names = [target.name, target.name&.demodulize].compact.uniq
        names.map(&:to_sym)
      end

      def identity_hash
        {}.compare_by_identity
      end
    end

    initializer "recording_studio_stripe.before_initialize", before: "recording_studio_stripe.load_config" do |_app|
      RecordingStudioStripe.configuration.hooks.run(:before_initialize, self)
    end

    initializer "recording_studio_stripe.load_config" do |app|
      if app.respond_to?(:config_for)
        begin
          yaml = begin
            app.config_for(:recording_studio_stripe)
          rescue StandardError
            nil
          end
          RecordingStudioStripe.configuration.merge!(yaml) if yaml.respond_to?(:each)
        rescue StandardError
          nil
        end
      end

      if app.config.respond_to?(:x) && app.config.x.respond_to?(:recording_studio_stripe)
        xcfg = app.config.x.recording_studio_stripe
        if xcfg.respond_to?(:to_h)
          RecordingStudioStripe.configuration.merge!(xcfg.to_h)
        else
          begin
            hash = {}
            xcfg.each_pair { |k, v| hash[k] = v } if xcfg.respond_to?(:each_pair)
            RecordingStudioStripe.configuration.merge!(hash) if hash&.any?
          rescue StandardError
            nil
          end
        end
      end

      RecordingStudioStripe.configuration.hooks.run(:on_configuration, RecordingStudioStripe.configuration)
    end

    initializer "recording_studio_stripe.after_initialize", after: "recording_studio_stripe.load_config" do |_app|
      RecordingStudioStripe.configuration.hooks.run(:after_initialize, self)
    end

    initializer "recording_studio_stripe.apply_model_extensions" do
      config.to_prepare do
        next unless defined?(ActiveRecord::Base)

        ActiveRecord::Base.descendants.each do |model|
          next if model.abstract_class?

          RecordingStudioStripe::Engine.apply_model_extensions(model)
        end
      end
    end

    initializer "recording_studio_stripe.apply_controller_extensions" do
      config.to_prepare do
        next unless defined?(ActionController::Base)

        ActionController::Base.descendants.each do |controller|
          RecordingStudioStripe::Engine.apply_controller_extensions(controller)
        end
      end
    end

    initializer "recording_studio_stripe.admin" do
      config.to_prepare do
        RecordingStudioStripe::Admin::Registration.register! if defined?(RecordingStudioAdmin)
      end
    end

    initializer "recording_studio_stripe.sync_meters" do
      config.to_prepare do
        next unless defined?(ActiveRecord::Base)
        next unless RecordingStudioStripe::Meter.table_exists?

        RecordingStudioStripe::Meter.sync_from_config!
      rescue ActiveRecord::ActiveRecordError
        nil
      end
    end

    initializer "recording_studio_stripe.append_migrations" do |app|
      engine_migrations = config.paths["db/migrate"].expanded
      next if engine_migrations.empty?

      app.config.paths["db/migrate"].concat(engine_migrations - app.config.paths["db/migrate"].expanded)
    end
  end
end

module ActionDispatch
  module Routing
    class Mapper
      def draw_recording_studio_stripe(at: "/billing", plans_path: "/plans", webhooks_path: "/webhooks/stripe")
        RecordingStudioStripe.configuration.mount_path = at
        post webhooks_path, to: "recording_studio_stripe/webhooks#create"
        get plans_path, to: "recording_studio_stripe/plans#index", as: :plans
        mount RecordingStudioStripe::Engine, at: at
      end
    end
  end
end
