class SuperAdmin::UsersController < SuperAdmin::ApplicationController
  # Overwrite any of the RESTful controller actions to implement custom behavior
  # For example, you may want to send an email after a foo is updated.

  def create
    resource = resource_class.new(resource_params)
    authorize_resource(resource)

    if resource.save
      redirect_to super_admin_user_path(resource), notice: translate_with_resource('create.success')
    else
      notice = resource.errors.full_messages.first
      redirect_to new_super_admin_user_path, notice: notice
    end
  end

  def update
    requested_resource.skip_reconfirmation! if resource_params[:confirmed_at].present?
    super
  end

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
  # def scoped_resource
  #   if current_user.super_admin?
  #     resource_class
  #   else
  #     resource_class.with_less_stuff
  #   end
  # end

  # Override `resource_params` if you want to transform the submitted
  # data before it's persisted. For example, the following would turn all
  # empty values into nil values. It uses other APIs such as `resource_class`
  # and `dashboard`:
  #

  def destroy_avatar
    avatar = requested_resource.avatar
    avatar.purge
    redirect_back(fallback_location: super_admin_users_path)
  end

  # Phase 15C (Issue #74): start impersonation. Gated by SuperAdmin auth + the Bloomwire platform-admin
  # boundary (SuperAdmin::ApplicationController before_actions), so only an approved platform admin reaches it.
  # The short-lived (5 min), single-use SSO token is generated on demand here (never rendered into a page href).
  # We emit the SSO handoff via `head` + Location instead of `redirect_to` so the token is not written to the
  # Rails "Redirected to ..." log line; it is also already filtered from request-parameter logs.
  def impersonate
    head :found, location: requested_resource.generate_sso_link_with_impersonation
  end

  def scoped_resource
    resource_class.with_attached_avatar
  end

  def resource_params
    permitted_params = super
    permitted_params.delete(:password) if permitted_params[:password].blank?
    # Phase 15A.2: never let the raw Users page set/change users.type when Bloomwire Mode is ON — platform-admin
    # identity is managed only via Bloomwire -> Platform Admins. (Defense-in-depth: the UserDashboard already
    # drops :type from form/permitted attributes in Mode ON.)
    permitted_params.delete(:type) if Bloomwire::Features.master_enabled?
    permitted_params
  end

  # See https://administrate-prototype.herokuapp.com/customizing_controller_actions
  # for more information
  def find_resource(param)
    super.becomes(User)
  end
end
