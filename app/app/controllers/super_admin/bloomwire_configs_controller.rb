class SuperAdmin::BloomwireConfigsController < SuperAdmin::ApplicationController
  def show
    @master_key = Bloomwire::Features::MASTER
    @master_enabled = Bloomwire::Features.master_enabled?
    @privacy_enabled = Bloomwire::Features.raw_enabled?(:privacy_hardening)
    @sub_features = Bloomwire::Features::SUB_FEATURES
    @privacy_dependent = Bloomwire::Features::PRIVACY_DEPENDENT_FEATURES
  end

  def create
    submitted = params.fetch(:bloomwire_config, {})
    persist(Bloomwire::Features::MASTER, submitted[Bloomwire::Features::MASTER]) if submitted.key?(Bloomwire::Features::MASTER)

    # Sub-features are inert while the master is OFF: ignore their params unless the master is (or is being turned) ON.
    persist_sub_features(submitted) if master_on_after_submit?(submitted)

    GlobalConfig.clear_cache
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_to super_admin_bloomwire_config_path, flash: { notice: 'Bloomwire settings updated.' }
    # rubocop:enable Rails/I18nLocaleTexts
  end

  private

  def persist_sub_features(submitted)
    privacy_on = Bloomwire::Features.raw_enabled?(:privacy_hardening)
    Bloomwire::Features::SUB_FEATURES.each do |feature, key|
      next unless submitted.key?(key)
      # Fail-closed: refuse managed-data toggles unless privacy hardening is already ON.
      next if Bloomwire::Features::PRIVACY_DEPENDENT_FEATURES.include?(feature) && !privacy_on

      persist(key, submitted[key])
    end
  end

  def persist(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = ActiveModel::Type::Boolean.new.cast(value) ? 'true' : 'false'
    config.locked = false
    config.save!
  end

  def master_on_after_submit?(submitted)
    return ActiveModel::Type::Boolean.new.cast(submitted[Bloomwire::Features::MASTER]) if submitted.key?(Bloomwire::Features::MASTER)

    Bloomwire::Features.master_enabled?
  end
end
