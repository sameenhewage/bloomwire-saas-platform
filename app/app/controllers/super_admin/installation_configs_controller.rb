class SuperAdmin::InstallationConfigsController < SuperAdmin::ApplicationController
  rescue_from ActiveRecord::RecordNotUnique, :with => :invalid_action_perfomed

  # Bloomwire: managed-data toggles must never be persisted ON through this generic config editor
  # while privacy hardening is OFF (architecture plan §4.1, ADR-0002 §5). This closes the path that
  # bypasses SuperAdmin::BloomwireConfigsController's guard.
  before_action :enforce_bloomwire_privacy_prerequisite, only: [:create, :update]
  # Overwrite any of the RESTful controller actions to implement custom behavior
  # For example, you may want to send an email after a foo is updated.
  #
  # def update
  #   super
  #   send_foo_updated_email(requested_resource)
  # end

  # Override this method to specify custom lookup behavior.
  # This will be used to set the resource for the `show`, `edit`, and `update`
  # actions.
  #
  # def find_resource(param)
  #   Foo.find_by!(slug: param)
  # end

  # The result of this lookup will be available as `requested_resource`

  # Override this if you have certain roles that require a subset
  # this will be used to set the records shown on the `index` action.
  #
  def scoped_resource
    resource_class.editable
  end

  def create
    resource = new_resource(resource_params)
    authorize_resource(resource)

    if resource.save
      redirect_to after_resource_created_path(resource), flash: success_flash(resource)
    else
      render :new, locals: {
        page: Administrate::Page::Form.new(dashboard, resource)
      }, status: :unprocessable_entity
    end
  end

  def update
    if requested_resource.update(resource_params)
      redirect_to after_resource_updated_path(requested_resource), flash: success_flash(requested_resource)
    else
      render :edit, locals: {
        page: Administrate::Page::Form.new(dashboard, requested_resource)
      }, status: :unprocessable_entity
    end
  end

  # Override `resource_params` if you want to transform the submitted
  # data before it's persisted. For example, the following would turn all
  # empty values into nil values. It uses other APIs such as `resource_class`
  # and `dashboard`:
  #
  # def resource_params
  #   params.require(resource_class.model_name.param_key).
  #     permit(dashboard.permitted_attributes).
  #     transform_values { |value| value == "" ? nil : value }
  # end

  def resource_params
    permitted = params.require(:installation_config)
                      .permit(:name, :value)
                      .transform_values { |value| value == '' ? nil : value }.merge(locked: false)
    # Bloomwire Phase 2A: never wipe a masked secret on a blank submit (the value is not echoed on the form).
    permitted.delete(:value) if blank_masked_secret_submission?(permitted)
    permitted
  end

  private

  def blank_masked_secret_submission?(permitted)
    return false if permitted[:value].present?

    name = permitted[:name].presence || (action_name == 'update' ? requested_resource.name : nil)
    Bloomwire::Features.masked_secret_key?(name)
  end

  def enforce_bloomwire_privacy_prerequisite
    name = bloomwire_config_name
    return unless Bloomwire::Features.privacy_dependent_key?(name)
    return unless ActiveModel::Type::Boolean.new.cast(resource_params[:value])
    return if Bloomwire::Features.raw_enabled?(:privacy_hardening)

    redirect_back fallback_location: super_admin_installation_configs_path,
                  alert: "#{name} cannot be enabled while BLOOMWIRE_PRIVACY_HARDENING is OFF."
  end

  def bloomwire_config_name
    resource_params[:name].presence || (action_name == 'update' ? requested_resource.name : nil)
  end

  def success_flash(resource)
    message = translate_with_resource('update.success')
    message = translate_with_resource('create.success') if action_name == 'create'
    return { notice: message } unless restart_required_config?(resource)

    { success: "#{message.delete_suffix('.')}. Restart Chatwoot web and worker processes to apply this change everywhere." }
  end

  def restart_required_config?(resource)
    resource.name.in?(InstallationConfig::RESTART_REQUIRED_CONFIG_KEYS)
  end

  # See https://administrate-prototype.herokuapp.com/customizing_controller_actions
  # for more information
end
