class Api::V1::Accounts::WebhooksController < Api::V1::Accounts::BaseController
  include Bloomwire::RestrictsAccountControlPlane

  before_action :check_authorization
  # Bloomwire managed mode: block business admins from webhook config. Runs after check_authorization
  # so agents stay on the stock policy path. OFF => stock.
  before_action :restrict_account_control_plane!, only: [:create, :update, :destroy]
  before_action :fetch_webhook, only: [:update, :destroy]

  def index
    @webhooks = Current.account.webhooks
  end

  def create
    @webhook = Current.account.webhooks.new(webhook_params)
    @webhook.save!
  end

  def update
    @webhook.update!(webhook_params)
  end

  def destroy
    @webhook.destroy!
    head :ok
  end

  private

  def webhook_params
    params.require(:webhook).permit(:inbox_id, :name, :url, subscriptions: [])
  end

  def fetch_webhook
    @webhook = Current.account.webhooks.find(params[:id])
  end
end
