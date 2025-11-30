require 'spec_helper'
require 'json'
require 'rails_helper'

RSpec.describe ActivityReporter do
  describe '#generate_report' do
    let(:reporter) { described_class.new }
    let(:user_id) { 42 }
    let(:now) { Time.utc(2023, 1, 1, 12, 0, 0) }

    before do
      allow(Time).to receive(:now).and_return(now)
    end

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
      end

      it 'returns an error report' do
        result = reporter.generate_report(user_id)
        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(now.iso8601)
      end
    end

    context 'when activities exist' do
      let(:activities) do
        [
          { 'timestamp' => '2023-01-01T10:15:00Z', 'action' => 'view' },
          { 'timestamp' => '2023-01-01T11:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-01-02T09:30:00Z', 'action' => 'view' }
        ]
      end

      let(:stats) do
        {
          total_actions: 120,
          unique_actions: 11,
          action_counts: { 'view' => 100, 'click' => 20 },
          first_activity: '2023-01-01T10:15:00Z',
          last_activity: '2023-01-02T09:30:00Z',
          most_frequent: 'view'
        }
      end

      let(:patterns_raw) do
        [
          { 'pattern_type' => 'burst', 'description' => 'morning spikes', 'confidence' => 0.8 },
          { 'pattern_type' => 'repeat', 'description' => 'daily login', 'confidence' => 0.9 },
          { 'pattern_type' => 'sequence', 'description' => 'view->click', 'confidence' => 0.7 }
        ]
      end

      let(:anomalies) do
        [{ 'id' => 1, 'type' => 'suspicious' }]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns_raw)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(80.5)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a comprehensive report with summary, breakdown, patterns, anomalies, timeline, and insights' do
        result = reporter.generate_report(user_id)

        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to eq(now.iso8601)

        expect(result[:summary]).to include(
          total_actions: 120,
          unique_actions: 11,
          engagement_score: 80.5,
          first_activity: '2023-01-01T10:15:00Z',
          last_activity: '2023-01-02T09:30:00Z'
        )

        expect(result[:action_breakdown]).to eq({ 'view' => 100, 'click' => 20 })

        expect(result[:patterns]).to eq([
                                          { type: 'burst', description: 'morning spikes', confidence: 0.8 },
                                          { type: 'repeat', description: 'daily login', confidence: 0.9 },
                                          { type: 'sequence', description: 'view->click', confidence: 0.7 }
                                        ])

        expect(result[:anomalies]).to eq(anomalies)

        expect(result[:timeline].size).to eq(2)
        first_day = result[:timeline].find { |e| e[:period] == '2023-01-01' }
        second_day = result[:timeline].find { |e| e[:period] == '2023-01-02' }

        expect(first_day[:total_actions]).to eq(2)
        expect(first_day[:actions]).to eq({ 'view' => 1, 'click' => 1 })
        expect(first_day[:first_timestamp]).to eq('2023-01-01T10:15:00Z')
        expect(first_day[:last_timestamp]).to eq('2023-01-01T11:00:00Z')

        expect(second_day[:total_actions]).to eq(1)
        expect(second_day[:actions]).to eq({ 'view' => 1 })
        expect(second_day[:first_timestamp]).to eq('2023-01-02T09:30:00Z')
        expect(second_day[:last_timestamp]).to eq('2023-01-02T09:30:00Z')

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('Diverse activity profile across multiple action types')
        expect(result[:insights]).to include('Clear behavioral patterns detected')
        expect(result[:insights]).to include('1 anomalous activities detected - review recommended')
        expect(result[:insights]).to include('Power user - high volume of activities')
      end

      it 'respects the provided group_by option for timeline' do
        result = reporter.generate_report(user_id, group_by: :hour)
        periods = result[:timeline].map { |e| e[:period] }
        expect(periods).to eq(['2023-01-01 10:00', '2023-01-01 11:00', '2023-01-02 09:00'])
      end
    end
  end

  describe '#format_timeline' do
    let(:reporter) { described_class.new }
    let(:now) { Time.utc(2023, 6, 10, 0, 0, 0) }

    before do
      allow(Time).to receive(:now).and_return(now)
    end

    it 'returns an empty array when activities are empty' do
      expect(reporter.format_timeline([])).to eq([])
    end

    it 'groups activities by day and sorts periods' do
      activities = [
        { 'timestamp' => '2023-01-02T09:30:00Z', 'action' => 'view' },
        { 'timestamp' => '2023-01-01T10:15:00Z', 'action' => 'view' },
        { 'timestamp' => '2023-01-01T11:00:00Z', 'action' => 'click' }
      ]

      timeline = reporter.format_timeline(activities, :day)
      expect(timeline.map { |e| e[:period] }).to eq(%w[2023-01-01 2023-01-02])

      first_day = timeline.first
      expect(first_day[:total_actions]).to eq(2)
      expect(first_day[:actions]).to eq({ 'view' => 1, 'click' => 1 })
      expect(first_day[:first_timestamp]).to eq('2023-01-01T10:15:00Z')
      expect(first_day[:last_timestamp]).to eq('2023-01-01T11:00:00Z')
    end

    it 'groups activities by hour' do
      activities = [
        { 'timestamp' => '2023-01-01T10:15:00Z', 'action' => 'view' },
        { 'timestamp' => '2023-01-01T10:45:00Z', 'action' => 'click' },
        { 'timestamp' => '2023-01-01T11:00:00Z', 'action' => 'view' }
      ]

      timeline = reporter.format_timeline(activities, :hour)
      expect(timeline.map { |e| e[:period] }).to eq(['2023-01-01 10:00', '2023-01-01 11:00'])

      ten_am = timeline.first
      expect(ten_am[:actions]).to eq({ 'view' => 1, 'click' => 1 })
      expect(ten_am[:first_timestamp]).to eq('2023-01-01T10:15:00Z')
      expect(ten_am[:last_timestamp]).to eq('2023-01-01T10:45:00Z')
    end

    it 'groups activities by ISO week' do
      activities = [
        { 'timestamp' => '2023-06-01T12:00:00Z', 'action' => 'view' },
        { 'timestamp' => '2023-06-08T12:00:00Z', 'action' => 'view' }
      ]

      timeline = reporter.format_timeline(activities, :week)
      expect(timeline.map { |e| e[:period] }).to eq(%w[2023-W22 2023-W23])
    end

    it 'groups activities by month' do
      activities = [
        { 'timestamp' => '2023-05-31T23:00:00Z', 'action' => 'view' },
        { 'timestamp' => '2023-06-01T00:30:00Z', 'action' => 'click' }
      ]

      timeline = reporter.format_timeline(activities, :month)
      expect(timeline.map { |e| e[:period] }).to eq(%w[2023-05 2023-06])
    end

    it 'defaults to day grouping for unknown group_by values' do
      activities = [
        { 'timestamp' => '2023-01-01T11:00:00Z', 'action' => 'click' },
        { 'timestamp' => '2023-01-01T12:00:00Z', 'action' => 'view' }
      ]

      timeline = reporter.format_timeline(activities, :unknown)
      expect(timeline.size).to eq(1)
      expect(timeline.first[:period]).to eq('2023-01-01')
      expect(timeline.first[:actions]).to eq({ 'click' => 1, 'view' => 1 })
    end

    it 'handles invalid timestamps by using current time' do
      activities = [
        { 'timestamp' => 'not-a-time', 'action' => 'err' }
      ]

      timeline = reporter.format_timeline(activities, :day)
      expect(timeline.size).to eq(1)
      expect(timeline.first[:period]).to eq('2023-06-10')
      expect(timeline.first[:actions]).to eq({ 'err' => 1 })
    end

    it 'preserves original order within a group for first and last timestamps' do
      activities = [
        { 'timestamp' => '2023-01-01T11:00:00Z', 'action' => 'click' },
        { 'timestamp' => '2023-01-01T10:15:00Z', 'action' => 'view' },
        { 'timestamp' => '2023-01-01T23:59:59Z', 'action' => 'view' }
      ]

      timeline = reporter.format_timeline(activities, :day)
      expect(timeline.size).to eq(1)
      entry = timeline.first
      expect(entry[:first_timestamp]).to eq('2023-01-01T11:00:00Z')
      expect(entry[:last_timestamp]).to eq('2023-01-01T23:59:59Z')
    end

    it 'sorts periods ascending regardless of input order' do
      activities = [
        { 'timestamp' => '2023-01-02T00:00:00Z', 'action' => 'view' },
        { 'timestamp' => '2023-01-01T00:00:00Z', 'action' => 'view' }
      ]

      timeline = reporter.format_timeline(activities, :day)
      expect(timeline.map { |e| e[:period] }).to eq(%w[2023-01-01 2023-01-02])
    end
  end

  describe '#export_to_json' do
    let(:reporter) { described_class.new }

    it 'returns pretty JSON data when filepath is not provided' do
      report = { foo: 'bar', count: 2 }
      result = reporter.export_to_json(report)
      expect(result[:success]).to eq(true)
      expect(result[:data]).to be_a(String)
      parsed = JSON.parse(result[:data])
      expect(parsed).to eq({ 'foo' => 'bar', 'count' => 2 })
    end

    it 'writes pretty JSON to a file when filepath is provided' do
      report = { name: 'alice', active: true }
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'report.json')
        result = reporter.export_to_json(report, path)
        expect(result[:success]).to eq(true)
        expect(result[:filepath]).to eq(path)
        expect(result[:size]).to eq(JSON.pretty_generate(report).bytesize)

        file_data = File.read(path)
        parsed = JSON.parse(file_data)
        expect(parsed).to eq({ 'name' => 'alice', 'active' => true })
      end
    end

    it 'returns an error when writing to file fails' do
      report = { test: 'x' }
      allow(File).to receive(:write).and_raise(StandardError.new('boom'))
      result = reporter.export_to_json(report, '/tmp/failure.json')
      expect(result[:success]).to eq(false)
      expect(result[:error]).to eq('boom')
    end
  end

  describe '#compare_users' do
    let(:reporter) { described_class.new }

    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users([1])
        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'with multiple users' do
      let(:user_ids) { [1, 2, 3] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with(1).and_return([{ 'timestamp' => 't', 'action' => 'a' }])
        allow(reporter).to receive(:fetch_user_activities).with(2).and_return([{ 'timestamp' => 't', 'action' => 'a' },
                                                                               { 'timestamp' => 't2',
                                                                                 'action' => 'b' }])
        allow(reporter).to receive(:fetch_user_activities).with(3).and_return([{ 'timestamp' => 't', 'action' => 'a' }])

        allow(reporter).to receive(:fetch_activity_stats).with(1).and_return(
          { total_actions: 10, unique_actions: 3, action_counts: { 'a' => 7 }, first_activity: 'f', last_activity: 'l',
            most_frequent: 'a' }
        )
        allow(reporter).to receive(:fetch_activity_stats).with(2).and_return(
          { total_actions: 5, unique_actions: 2, action_counts: { 'b' => 3 }, first_activity: 'f', last_activity: 'l',
            most_frequent: 'b' }
        )
        allow(reporter).to receive(:fetch_activity_stats).with(3).and_return(
          { total_actions: 8, unique_actions: 2, action_counts: { 'c' => 5 }, first_activity: 'f', last_activity: 'l',
            most_frequent: 'c' }
        )

        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => 't', 'action' => 'a' }]).and_return(50.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => 't', 'action' => 'a' },
                                                            { 'timestamp' => 't2', 'action' => 'b' }]).and_return(80.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => 't', 'action' => 'a' }]).and_return(50.0) # For user 3 identical activities array literal might be different object; stub specifically:
        allow(reporter).to receive(:fetch_user_score).with(array_including(hash_including('timestamp' => 't'))).and_return(50.0)
      end

      it 'returns comparisons sorted by engagement_score with top user and average score' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].size).to eq(3)

        # Sorted by engagement_score descending: user 2 (80.0), then 1/3 (50.0)
        expect(result[:comparisons].first[:user_id]).to eq(2)
        expect(result[:comparisons].first[:engagement_score]).to eq(80.0)
        expect(result[:comparisons].first[:total_actions]).to eq(5)
        expect(result[:comparisons].first[:most_frequent_action]).to eq('b')

        expect(result[:top_user]).to eq(2)
        expect(result[:average_score]).to eq(63.33)
      end
    end
  end
end
