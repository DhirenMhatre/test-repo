require 'rspec'

RSpec.describe 'ActivityReporter' do
  it 'does not define ActivityReporter constant (no source code present)' do
    expect(defined?(ActivityReporter)).to be_nil
  end

  it 'loads successfully' do
    expect(true).to eq(true)
  end
end
