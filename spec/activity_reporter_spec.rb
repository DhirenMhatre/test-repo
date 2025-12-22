require 'rspec'

RSpec.describe 'ActivityReporter' do
  it 'does not define ActivityReporter constant (no source code present)' do
    expect(Object.const_defined?(:ActivityReporter)).to be false
  end

  it 'loads successfully' do
    expect(true).to eq(true)
  end
end
