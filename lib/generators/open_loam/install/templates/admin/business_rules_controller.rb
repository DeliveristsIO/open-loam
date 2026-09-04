module Admin
  # Managing business rules (Loam::BusinessRule) — manager-only, since a rule can
  # notify, emit events, and set fields across the tenant. The condition and
  # actions are edited as JSON for the prototype (a visual builder is a future
  # increment). The recent execution log shows WHY rules fired.
  class BusinessRulesController < BaseController
    before_action { require_role!(:manager) }
    before_action :set_rule, only: %i[edit update destroy]

    rescue_from JSON::ParserError do |error|
      flash.now[:alert] = "Condition and actions must be valid JSON: #{error.message}"
      @rule ||= Loam::BusinessRule.new
      render(@rule.persisted? ? :edit : :new, status: :unprocessable_entity)
    end

    def index
      @rules = Loam::BusinessRule.by_priority
      @recent_runs = Loam::BusinessRuleRun.recent.limit(20)
    end

    def new
      @rule = Loam::BusinessRule.new(active: true, condition: {}, actions: [])
    end

    def create
      @rule = Loam::BusinessRule.new(rule_params)
      if @rule.save
        redirect_to admin_business_rules_path, notice: "Rule created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @rule.update(rule_params)
        redirect_to admin_business_rules_path, notice: "Rule updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @rule.destroy!
      redirect_to admin_business_rules_path, notice: "Rule deleted."
    end

    private

    def set_rule
      @rule = Loam::BusinessRule.find(params[:id])
    end

    # Parse the JSON textareas here; a malformed value raises JSON::ParserError,
    # which the rescue above turns into a form error (never a 500).
    def rule_params
      attributes = params.require(:business_rule).permit(:name, :entity_type, :trigger, :active, :priority)
      attributes[:condition] = JSON.parse(params[:business_rule][:condition].presence || "{}")
      attributes[:actions] = JSON.parse(params[:business_rule][:actions].presence || "[]")
      attributes
    end
  end
end
