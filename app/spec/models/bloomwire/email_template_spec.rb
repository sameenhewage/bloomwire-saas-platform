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

  describe 'system template key immutability' do
    it 'prevents changing the key of a system template' do
      template = described_class.create!(key: 'sys_one', name: 'N', subject: 's', body: 'b', system: true)
      expect(template.update(key: 'hacked')).to be(false)
      expect(template.errors.attribute_names).to include(:key)
      expect(template.reload.key).to eq('sys_one')
    end

    it 'still allows changing safe fields on a system template' do
      template = described_class.create!(key: 'sys_two', name: 'N', subject: 's', body: 'b', system: true)
      expect(template.update(subject: 'New subject', name: 'New name', active: false)).to be(true)
      expect(template.reload.subject).to eq('New subject')
      expect(template.active).to be(false)
    end

    it 'keeps seeded system keys stable across re-seeding' do
      described_class.seed_defaults!
      described_class.find_by(key: 'welcome_email').update!(subject: 'Owner edited')
      described_class.seed_defaults! # idempotent re-run must not reset or duplicate
      expect(described_class.where(key: 'welcome_email').count).to eq(1)
      expect(described_class.find_by(key: 'welcome_email').subject).to eq('Owner edited')
    end
  end

  describe 'cta_url scheme validation' do
    it 'allows http(s) URLs, {{variable}} placeholders, and blank' do
      expect(described_class.new(key: 'a', name: 'n', subject: 's', body: 'b', cta_url: 'https://x.com')).to be_valid
      expect(described_class.new(key: 'b', name: 'n', subject: 's', body: 'b', cta_url: '{{invitation_link}}')).to be_valid
      expect(described_class.new(key: 'c', name: 'n', subject: 's', body: 'b', cta_url: '')).to be_valid
    end

    it 'rejects javascript: and other unsafe schemes' do
      template = described_class.new(key: 'd', name: 'n', subject: 's', body: 'b', cta_url: 'javascript:alert(1)')
      expect(template).not_to be_valid
      expect(template.errors.attribute_names).to include(:cta_url)
    end
  end

  describe '#used_variables (Phase 15F.2 dynamic parsing)' do
    it 'extracts variables from subject, body AND cta link, de-duplicated and in first-seen order' do
      template = described_class.new(
        subject: 'Order {{custom_order_id}} for {{recipient_name}}',
        body: 'Hi {{recipient_name}}, your order {{custom_order_id}} ships to {{business_name}}.',
        cta_url: '{{tracking_link}}'
      )
      expect(template.used_variables).to eq(%w[custom_order_id recipient_name business_name tracking_link])
    end

    it 'detects CUSTOM variables, not only the known VARIABLES list' do
      template = described_class.new(subject: 's', body: 'Ref {{custom_order_id}}')
      expect(template.used_variables).to include('custom_order_id')
      expect(described_class::VARIABLES).not_to include('custom_order_id')
    end

    it 'returns nothing for a template with no placeholders' do
      expect(described_class.new(subject: 'Hello', body: 'No variables here').used_variables).to eq([])
    end

    it 'detects a variable used ONLY in the CTA button label (review fix)' do
      template = described_class.new(subject: 'Hi', body: 'Static body',
                                     cta_label: 'Open {{business_name}}', cta_url: 'https://x.test')
      expect(template.used_variables).to include('business_name')
    end
  end

  describe '#composition_for (Phase 15F.2 — single resolver for preview AND send)' do
    let(:template) do
      described_class.new(subject: 'Hi {{recipient_name}}', body: 'Join {{business_name}} now', cta_label: 'Go',
                          cta_url: '{{invitation_link}}')
    end

    it 'renders fully and reports no missing variables when every value is supplied' do
      out = template.composition_for('recipient_name' => 'Rita', 'business_name' => 'Globex',
                                     'invitation_link' => 'https://x.test/i')
      expect(out[:subject]).to eq('Hi Rita')
      expect(out[:body]).to eq('Join Globex now')
      expect(out[:cta_url]).to eq('https://x.test/i')
      expect(out[:body]).not_to match(/\{\{.*?\}\}/)
      expect(out[:missing_variables]).to eq([])
    end

    it 'leaves a blank variable as a visible {{placeholder}} and NEVER substitutes sample data' do
      out = template.composition_for('recipient_name' => 'Rita', 'business_name' => '',
                                     'invitation_link' => 'https://x.test/i')
      expect(out[:subject]).to eq('Hi Rita')
      expect(out[:body]).to eq('Join {{business_name}} now')        # raw placeholder, not the SAMPLE value
      expect(out[:body]).not_to include('Bloomwire (Pvt) Ltd')      # SAMPLE_VARS['business_name'] must not leak
      expect(out[:missing_variables]).to eq(['business_name'])
    end

    it 'interpolates the CTA label and flags a blank CTA-only variable as missing (review fix)' do
      cta_template = described_class.new(subject: 'Hi', body: 'Static body',
                                         cta_label: 'Open {{business_name}}', cta_url: 'https://x.test')
      filled = cta_template.composition_for('business_name' => 'Globex')
      expect(filled[:cta_label]).to eq('Open Globex')
      expect(filled[:missing_variables]).to eq([])

      blank = cta_template.composition_for('business_name' => '')
      expect(blank[:cta_label]).to eq('Open {{business_name}}')     # raw placeholder, not sampled
      expect(blank[:missing_variables]).to eq(['business_name'])
    end
  end
end
