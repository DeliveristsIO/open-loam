module Admin
  # Per-tenant settings (Loam::Configs). Structural, not per-record, so it is
  # gated on the manager role rather than an entity policy — settings are
  # privileged. Everything routes through Loam::Configs, never Loam::Config
  # directly, so the cross-level resolution stays in vetted gem code.
  class ConfigsController < BaseController
    before_action { require_role!(:manager) }

    def index
      @settings = Loam::Configs.defined_keys.map do |key|
        { key: key, value: Loam::Configs.get(key), overridden: Loam::Configs.overridden?(key) }
      end
    end

    def edit
      @key = params[:key]
      @value = Loam::Configs.get(@key)
      @overridden = Loam::Configs.overridden?(@key)
    end

    def update
      Loam::Configs.set(params[:key], coerce(params[:value]))
      redirect_to admin_configs_path, notice: "#{params[:key]} set for this tenant."
    end

    def reset
      Loam::Configs.reset(params[:key])
      redirect_to admin_configs_path, notice: "#{params[:key]} reset to the default."
    end

    private

    # The form is a single text field, so values arrive as strings. Parse them
    # as JSON so numbers/booleans/objects keep their type; anything that is not
    # valid JSON (a bare word like PLN) is stored as the string it is. Known
    # quirk: typing 25 stores the number, never the string "25" — fine here.
    def coerce(raw)
      JSON.parse(raw)
    rescue JSON::ParserError
      raw
    end
  end
end
