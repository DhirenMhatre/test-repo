require 'spec_helper'
require 'json'
require 'tmpdir'
require 'time'
require 'rails_helper'

RSpec.describe ActivityReporter do
  describe '#generate_report' do
    let(:reporter) { described_class.new }
    let(:user_id) { 'u1' }

    context 'when activities exist' do
      let(:activities) do
        [
          { 'timestamp' => '2024-01-01T10:30:00Z', 'action' => 'login' },
          { 'timestamp' => '2024-01-01T11:15:00Z', 'action' => 'click' },
          { 'timestamp' => '2024-01-02T08:05:00Z', 'action' => 'logout' }
        ]
      end

      let(:stats) do
        {
          total_actions: 3,
          unique_actions: 3,
          action_counts: { 'login' => 1, 'click' => 1, 'logout' => 1 },
          first_activity: '2024-01-01T10:30:00Z',
          last_activity: '2024-01-02T08:05:00Z',
          most_frequent: 'login'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'burst', 'description' => 'Activity spike', 'confidence' => 0.9 },
          { 'pattern_type' => 'routine', 'description' => 'Daily login', 'confidence' => 0.8 },
          { 'pattern_type' => 'weekly', 'description' => 'Weekly summary', 'confidence' => 0.7 }
        ]
      end

      let(:user_score) { 80.5 }
      let(:anomalies) { [{ 'id' => 1 }, { 'id' => 2 }] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'returns a comprehensive report with expected structure and content' do
        result = reporter.generate_report(user_id, group_by: :day)

        expect(result[:user_id]).to eq(user_id)
        expect(result[:summary][:total_actions]).to eq(3)
        expect(result[:summary][:unique_actions]).to eq(3)
        expect(result[:summary][:engagement_score]).to eq(80.5)
        expect(result[:summary][:first_activity]).to eq('2024-01-01T10:30:00Z')
        expect(result[:summary][:last_activity]).to eq('2024-01-02T08:05:00Z')
        expect(result[:action_breakdown]).to eq('login' => 1, 'click' => 1, 'logout' => 1)

        expected_patterns = [
          { type: 'burst', description: 'Activity spike', confidence: 0.9 },
          { type: 'routine', description: 'Daily login', confidence: 0.8 },
          { type: 'weekly', description: 'Weekly summary', confidence: 0.7 }
        ]
        expect(result[:patterns]).to eq(expected_patterns)

        expect(result[:anomalies]).to eq(anomalies)

        expect(result[:timeline].size).to eq(2)
        expect(result[:timeline][0][:period]).to eq('2024-01-01')
        expect(result[:timeline][0][:total_actions]).to eq(2)
        expect(result[:timeline][0][:actions]).to eq('login' => 1, 'click' => 1)
        expect(result[:timeline][0][:first_timestamp]).to eq('2024-01-01T10:30:00Z')
        expect(result[:timeline][0][:last_timestamp]).to eq('2024-01-01T11:15:00Z')

        expect(result[:timeline][1][:period]).to eq('2024-01-02')
        expect(result[:timeline][1][:total_actions]).to eq(1)
        expect(result[:timeline][1][:actions]).to eq('logout' => 1)

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('Clear behavioral patterns detected')
        expect(result[:insights]).to include('2 anomalous activities detected - review recommended')
        expect(result[:insights]).not_to include('Power user - high volume of activities')
        expect(result[:insights]).not_to include('Diverse activity profile across multiple action types')

        expect(result[:generated_at]).to be_a(String)
        expect do
          Time.iso8601(result[:generated_at])
        end.not_to raise_error
      end
    end

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
      end

      it 'returns an error report with message' do
        result = reporter.generate_report(user_id)
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to be_a(String)
      end
    end
  end

  describe '#format_timeline' do
    let(:reporter) { described_class.new }

    context 'when activities are empty' do
      it 'returns an empty array' do
        result = reporter.format_timeline([], :day)
        expect(result).to eq([])
      end
    end

    context 'grouped by day' do
      let(:activities) do
        [
          { 'timestamp' => '2024-01-02T09:00:00Z', 'action' => 'view' },
          { 'timestamp' => '2024-01-02T10:00:00Z', 'action' => 'view' },
          { 'timestamp' => '2024-01-03T11:00:00Z', 'action' => 'click' }
        ]
      end

      it 'groups activities per day with correct counts and ordering' do
        result = reporter.format_timeline(activities, :day)
        expect(result.map { |r| r[:period] }).to eq(%w[2024-01-02 2024-01-03])
        expect(result[0][:total_actions]).to eq(2)
        expect(result[0][:actions]).to eq('view' => 2)
        expect(result[1][:total_actions]).to eq(1)
        expect(result[1][:actions]).to eq('click' => 1)
      end
    end

    context 'grouped by hour' do
      let(:activities) do
        [
          { 'timestamp' => '2024-01-02T09:15:00Z', 'action' => 'view' },
          { 'timestamp' => '2024-01-02T09:45:00Z', 'action' => 'click' },
          { 'timestamp' => '2024-01-02T10:05:00Z', 'action' => 'view' }
        ]
      end

      it 'groups activities per hour with correct labels' do
        result = reporter.format_timeline(activities, :hour)
        expect(result.map { |r| r[:period] }).to eq(['2024-01-02 09:00', '2024-01-02 10:00'])
        expect(result[0][:actions]).to eq('view' => 1, 'click' => 1)
        expect(result[1][:actions]).to eq('view' => 1)
      end
    end

    context 'grouped by week' do
      let(:activities) do
        [
          { 'timestamp' => '2024-01-01T12:00:00Z', 'action' => 'login' },
          { 'timestamp' => '2024-01-08T12:00:00Z', 'action' => 'logout' }
        ]
      end

      it 'groups activities per ISO week with correct labels' do
        result = reporter.format_timeline(activities, :week)
        expect(result.map { |r| r[:period] }).to eq(%w[2024-W01 2024-W02])
        expect(result[0][:actions]).to eq('login' => 1)
        expect(result[1][:actions]).to eq('logout' => 1)
      end
    end

    context 'grouped by month' do
      let(:activities) do
        [
          { 'timestamp' => '2024-01-31T23:00:00Z', 'action' => 'a' },
          { 'timestamp' => '2024-02-01T00:00:00Z', 'action' => 'b' }
        ]
      end

      it 'groups activities per month with correct labels' do
        result = reporter.format_timeline(activities, :month)
        expect(result.map { |r| r[:period] }).to eq(%w[2024-01 2024-02])
        expect(result[0][:actions]).to eq('a' => 1)
        expect(result[1][:actions]).to eq('b' => 1)
      end
    end

    context 'with invalid timestamp strings' do
      let(:activities) do
        [
          { 'timestamp' => 'INVALID', 'action' => 'oops' }
        ]
      end

      after do
        allow(Time).to receive(:now).and_call_original
      end

      it 'falls back to Time.now and still produces a timeline entry' do
        fixed = Time.utc(2023, 12, 25, 10, 15, 20)
        allow(Time).to receive(:now).and_return(fixed)

        result = reporter.format_timeline(activities, :day)
        expect(result.length).to eq(1)
        expect(result[0][:period]).to eq('2023-12-25')
        expect(result[0][:total_actions]).to eq(1)
        expect(result[0][:actions]).to eq('oops' => 1)
        expect(result[0][:first_timestamp]).to eq('INVALID')
        expect(result[0][:last_timestamp]).to eq('INVALID')
      end
    end
  end

  describe '#export_to_json' do
    let(:reporter) { described_class.new }
    let(:report) do
      {
        user_id: 'u1',
        summary: { total_actions: 2 },
        timeline: [],
        generated_at: '2024-01-01T00:00:00Z'
      }
    end

    context 'when filepath is provided' do
      it 'writes pretty JSON to the file and returns metadata' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(report, path)

          expect(result[:success]).to be true
          expect(result[:filepath]).to eq(path)
          expect(File.exist?(path)).to be true

          content = File.read(path)
          expect(JSON.parse(content)).to eq(JSON.parse(JSON.pretty_generate(report)))
          expect(result[:size]).to eq(content.bytesize)
        end
      end
    end

    context 'when filepath is not provided' do
      it 'returns the JSON string data' do
        result = reporter.export_to_json(report)
        expect(result[:success]).to be true
        expect(result[:data]).to be_a(String)
        expect(JSON.parse(result[:data])).to eq(JSON.parse(JSON.pretty_generate(report)))
      end
    end

    context 'when file writing fails' do
      after do
        allow(File).to receive(:write).and_call_original
      end

      it 'returns an error response' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          allow(File).to receive(:write).and_raise(StandardError.new('disk full'))

          result = reporter.export_to_json(report, path)
          expect(result[:success]).to be false
          expect(result[:error]).to eq('disk full')
        end
      end
    end
  end

  describe '#compare_users' do
    let(:reporter) { described_class.new }

    context 'when fewer than 2 user IDs are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['u1'])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
      end
    end

    context 'with multiple users' do
      let(:user_ids) { %w[u1 u2 u3] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([{
                                                                                   'timestamp' => '2024-01-01T00:00:00Z', 'action' => 'login'
                                                                                 }])
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return([{
                                                                                   'timestamp' => '2024-01-01T01:00:00Z', 'action' => 'click'
                                                                                 }])
        allow(reporter).to receive(:fetch_user_activities).with('u3').and_return([{
                                                                                   'timestamp' => '2024-01-01T02:00:00Z', 'action' => 'purchase'
                                                                                 }])

        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return({ total_actions: 10, unique_actions: 2,
                                                                                  action_counts: { 'login' => 6, 'click' => 4 }, first_activity: '2024-01-01T00:00:00Z', last_activity: '2024-01-01T02:00:00Z', most_frequent: 'login' })
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return({ total_actions: 50, unique_actions: 3,
                                                                                  action_counts: { 'click' => 40, 'view' => 10 }, first_activity: '2024-01-01T01:00:00Z', last_activity: '2024-01-02T02:00:00Z', most_frequent: 'click' })
        allow(reporter).to receive(:fetch_activity_stats).with('u3').and_return({ total_actions: 20, unique_actions: 4,
                                                                                  action_counts: { 'purchase' => 12, 'view' => 8 }, first_activity: '2024-01-01T02:00:00Z', last_activity: '2024-01-03T02:00:00Z', most_frequent: 'purchase' })

        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2024-01-01T00:00:00Z',
                                                              'action' => 'login' }]).and_return(20)
        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2024-01-01T01:00:00Z',
                                                              'action' => 'click' }]).and_return(80)
        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2024-01-01T02:00:00Z',
                                                              'action' => 'purchase' }]).and_return(50)
      end

      it 'sorts users by engagement score descending and computes summary stats' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:top_user]).to eq('u2')
        expect(result[:average_score]).to eq(50.0)

        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(%w[u2 u3 u1])
        expect(result[:comparisons][0][:engagement_score]).to eq(80)
        expect(result[:comparisons][1][:engagement_score]).to eq(50)
        expect(result[:comparisons][2][:engagement_score]).to eq(20)

        expect(result[:comparisons][0][:total_actions]).to eq(50)
        expect(result[:comparisons][0][:most_frequent_action]).to eq('click')
        expect(result[:comparisons][1][:total_actions]).to eq(20)
        expect(result[:comparisons][1][:most_frequent_action]).to eq('purchase')
        expect(result[:comparisons][2][:total_actions]).to eq(10)
        expect(result[:comparisons][2][:most_frequent_action]).to eq('login')
      end
    end
  end
end
