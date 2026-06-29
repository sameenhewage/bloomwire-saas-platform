require 'rails_helper'

# Phase 15F: Bloomwire-owned email template model. Variable interpolation + system seeding + duplicate.
RSpec.describe Bloomwire::EmailTemplate do
  describe 'validations' do
    it 'requires key, name, subject and body' do
      template = described_class.new
      expect(template).not_to be_valid
      expect(template.errors.attribute_names).to include(:key, :name, :subject, :body)
    end

    it 'enforces a unique key' do
      described_class.create!(key: 'dup', name: 'A', subject: 's', body: 'b')
      expect(described_class.new(key: 'dup', name: 'B', subject: 's', body: 'b')).not_to be_valid
    end
  end

  describe '.interpolate' do
    it 'replaces known variables and leaves unknown ones intact' do
      out = described_class.interpolate('Hi {{recipient_name}} / {{mystery}}', { 'recipient_name' => 'Sam' })
      expect(out).to eq('Hi Sam / {{mystery}}')
    end
  end

  describe '#render_subject / #render_body' do
    it 'renders with the default sample variables' do
      template = described_class.new(subject: 'Join {{business_name}}', body: 'Hi {{recipient_name}}')
      expect(template.render_subject).to include('Bloomwire (Pvt) Ltd')
      expect(template.render_body).to include('Sameen Hewage')
      expect(template.render_body).not_to include('{{recipient_name}}')
    end
  end

  describe '.seed_defaults!' do
    it 'creates the six system templates idempotently' do
      expect { described_class.seed_defaults! }.to change(described_class, :count).by(6)
      expect { described_class.seed_defaults! }.not_to change(described_class, :count)
      expect(described_class.where(system: true).count).to eq(6)
      expect(described_class.pluck(:key)).to include('new_business_invitation', 'password_reset', 'support_ticket_update')
    end
  end

  describe '#duplicate!' do
    it 'creates an inactive, non-system copy with a unique key' do
      described_class.seed_defaults!
      original = described_class.find_by(key: 'welcome_email')
      copy = original.duplicate!
      expect(copy.active).to be(false)
      expect(copy.system).to be(false)
      expect(copy.key).not_to eq(original.key)
      expect(copy.name).to include('Copy')
    end
  end

  describe '#deactivate! / #activate!' do
    it 'toggles active' do
      template = described_class.create!(key: 'k', name: 'n', subject: 's', body: 'b')
      template.deactivate!
      expect(template.reload.active).to be(false)
      template.activate!
      expect(template.reload.active).to be(true)
    end
  end
end
