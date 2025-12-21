require 'rspec'

RSpec.describe 'ActivityReporter' do
  it 'is implemented in this project' do
    expect(defined?(::ActivityReporter)).not_to be_nil
  end
end
