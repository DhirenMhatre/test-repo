require 'rspec'

describe 'ActivityReporter loading' do
  let(:activity_reporter_path) do
    File.expand_path('lib/activity_reporter.rb', __dir__)
  end

  it 'does not have a source file present in the repository' do
    expect(File.exist?(activity_reporter_path)).to be(false)
  end

  it 'raises LoadError when required via relative path' do
    expect do
      require_relative '../lib/activity_reporter'
    end.to raise_error(LoadError)
  end
end
