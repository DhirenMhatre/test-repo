require 'rspec'

describe 'ActivityReporter loading' do
  let(:root_path) do
    File.expand_path('..', __dir__)
  end

  let(:activity_reporter_path) do
    File.join(root_path, 'lib', 'activity_reporter.rb')
  end

  it 'does not crash when checking for file presence' do
    expect { File.exist?(activity_reporter_path) }.not_to raise_error
  end

  context 'library file' do
    it 'is not present in the repository' do
      expect(File.exist?(activity_reporter_path)).to be(false)
    end

    it 'raises LoadError when required' do
      expect do
        require_relative '../lib/activity_reporter'
      end.to raise_error(LoadError)
    end
  end
end
