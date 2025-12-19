describe 'ActivityReporter loading' do
  let(:root_path) do
    File.expand_path('..', __dir__)
  end

  let(:activity_reporter_path) do
    File.join(root_path, 'lib', 'activity_reporter.rb')
  end

  it 'has a source file present in the repository' do
    expect(File.exist?(activity_reporter_path)).to be(true)
  end

  it 'loads successfully when required via relative path' do
    expect do
      require_relative '../lib/activity_reporter'
    end.not_to raise_error
  end
end
