require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  let(:generator) { described_class.new }

  before do
    stub_const('User', Class.new)
  end

  describe '#generate_user_report' do
    let(:posts1) { double('posts', count: 3) }
    let(:posts2) { double('posts', count: 0) }
    let(:user1) { double('user', name: 'Alice', posts: posts1) }
    let(:user2) { double('user', name: 'Bob', posts: posts2) }

    before do
      allow(User).to receive(:find) do |id|
        if id == 1
          user1
        elsif id == 2
          user2
        else
          raise "Unexpected id #{id}"
        end
      end
    end

    context 'with multiple user ids' do
      let(:user_ids) { [1, 2] }

      it 'queries each user, outputs post counts, and returns the original ids' do
        expected_output = "Alice: 3 posts\nBob: 0 posts\n"
        expect do
          result = generator.generate_user_report(user_ids)
          expect(result).to eq(user_ids)
        end.to output(expected_output).to_stdout
      end
    end

    context 'with an empty list' do
      it 'prints nothing and returns an empty array' do
        expect do
          result = generator.generate_user_report([])
          expect(result).to eq([])
        end.to output('').to_stdout
      end
    end

    context 'when a lookup raises an error' do
      it 'propagates the error' do
        allow(User).to receive(:find) do |id|
          raise 'boom' unless id == 1

          user1
        end
        expect do
          generator.generate_user_report([1, 2])
        end.to raise_error(RuntimeError, 'boom')
      end
    end

    context 'when posts does not respond to count' do
      it 'raises NoMethodError' do
        bad_user = double('user', name: 'Carol', posts: double('posts'))
        allow(User).to receive(:find) do |id|
          if id == 1
            bad_user
          else
            user2
          end
        end
        expect do
          generator.generate_user_report([1, 2])
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    let(:record1) { double('record', id: 1, name: 'Alice') }
    let(:record2) { double('record', id: 2, name: 'Bob') }

    context 'with multiple records' do
      it 'concatenates rows into a CSV-like string' do
        result = generator.build_csv([record1, record2])
        expect(result).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with empty records' do
      it 'returns an empty string' do
        result = generator.build_csv([])
        expect(result).to eq('')
      end
    end

    context 'when a record has nil fields' do
      it 'includes empty fields for nil values' do
        record = double('record', id: 3, name: nil)
        result = generator.build_csv([record])
        expect(result).to eq("3,\n")
      end
    end

    context 'when a record is nil' do
      it 'raises NoMethodError' do
        expect do
          generator.build_csv([record1, nil])
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    context 'with overlapping values' do
      it 'returns matches for values present in both lists' do
        result = generator.find_matches([1, 2, 3], [2, 3, 4])
        expect(result).to match_array([2, 3])
      end
    end

    context 'with duplicates in both lists' do
      it 'returns multiplicities for each matching pair' do
        result = generator.find_matches([2, 2], [2, 2])
        expect(result).to eq([2, 2, 2, 2])
      end
    end

    context 'with disjoint lists' do
      it 'returns an empty array' do
        result = generator.find_matches([1, 2], [3, 4])
        expect(result).to eq([])
      end
    end

    context 'with mixed types that do not match' do
      it 'does not coerce types and returns empty' do
        result = generator.find_matches([1, 2], %w[1 2])
        expect(result).to eq([])
      end
    end

    context 'when list_a is nil' do
      it 'raises NoMethodError' do
        expect do
          generator.find_matches(nil, [])
        end.to raise_error(NoMethodError)
      end
    end

    context 'when list_b is nil' do
      it 'raises NoMethodError' do
        expect do
          generator.find_matches([1], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    let(:user_a) { double('user_a') }
    let(:user_b) { double('user_b') }

    context 'when there are users' do
      before do
        allow(User).to receive(:all).and_return([user_a, user_b])
      end

      it 'calls send_email for each user' do
        expect(generator).to receive(:send_email).with(user_a)
        expect(generator).to receive(:send_email).with(user_b)
        generator.process_all_users
      end
    end

    context 'when there are no users' do
      it 'does not call send_email' do
        allow(User).to receive(:all).and_return([])
        expect(generator).not_to receive(:send_email)
        generator.process_all_users
      end
    end

    context 'when User.all raises an error' do
      it 'propagates the error' do
        allow(User).to receive(:all).and_raise(StandardError, 'db down')
        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'db down')
      end
    end

    context 'when send_email raises an error' do
      it 'propagates the error' do
        allow(User).to receive(:all).and_return([user_a])
        allow(generator).to receive(:send_email).with(user_a).and_raise('smtp error')
        expect do
          generator.process_all_users
        end.to raise_error('smtp error')
      end
    end
  end
end
