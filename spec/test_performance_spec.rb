require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  describe '#generate_user_report' do
    let(:generator) do
      described_class.new
    end

    before do
      stub_const('User', Class.new)
    end

    context 'with valid user_ids' do
      let(:posts1) do
        double('Posts1', count: 2)
      end

      let(:posts2) do
        double('Posts2', count: 0)
      end

      let(:user1) do
        instance_double('User', name: 'Alice', posts: posts1)
      end

      let(:user2) do
        instance_double('User', name: 'Bob', posts: posts2)
      end

      before do
        allow(User).to receive(:find).with(1).and_return(user1)
        allow(User).to receive(:find).with(2).and_return(user2)
      end

      it 'queries each user id and prints a line per user' do
        expect(User).to receive(:find).with(1).once.and_return(user1)
        expect(User).to receive(:find).with(2).once.and_return(user2)
        expect(user1).to receive(:posts).and_return(posts1)
        expect(user2).to receive(:posts).and_return(posts2)
        expected_output = "Alice: 2 posts\nBob: 0 posts\n"
        expect do
          generator.generate_user_report([1, 2])
        end.to output(expected_output).to_stdout
      end
    end

    context 'with empty user_ids' do
      it 'does not query and outputs nothing' do
        expect(User).not_to receive(:find)
        expect do
          generator.generate_user_report([])
        end.to output('').to_stdout
      end
    end

    context 'when User.find raises an error' do
      before do
        allow(User).to receive(:find).and_raise(StandardError, 'not found')
      end

      it 'propagates the error' do
        expect do
          generator.generate_user_report([1])
        end.to raise_error(StandardError, 'not found')
      end
    end

    context 'with nil input' do
      it 'raises an error' do
        expect do
          generator.generate_user_report(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    let(:generator) do
      described_class.new
    end

    context 'with multiple records' do
      let(:record1) do
        double('Record', id: 1, name: 'Alice')
      end

      let(:record2) do
        double('Record', id: 2, name: 'Bob')
      end

      it 'returns concatenated CSV string' do
        result = generator.build_csv([record1, record2])
        expect(result).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with an empty array' do
      it 'returns an empty string' do
        result = generator.build_csv([])
        expect(result).to eq('')
      end
    end

    context 'with names containing commas' do
      let(:record) do
        double('Record', id: 1, name: 'A, B')
      end

      it 'does not escape commas and returns raw concatenation' do
        result = generator.build_csv([record])
        expect(result).to eq("1,A, B\n")
      end
    end

    context 'with nil input' do
      it 'raises an error' do
        expect do
          generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end

    context 'with a record missing attributes' do
      let(:bad_record) do
        double('BadRecord')
      end

      it 'raises an error when accessing missing attributes' do
        expect do
          generator.build_csv([bad_record])
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    let(:generator) do
      described_class.new
    end

    context 'with overlapping elements' do
      it 'returns the common elements' do
        result = generator.find_matches([1, 2, 3], [2, 3, 4])
        expect(result).to match_array([2, 3])
      end
    end

    context 'with duplicates in both lists' do
      it 'returns each match for each pairing (cartesian multiplicity)' do
        result = generator.find_matches([1, 1], [1, 1])
        expect(result).to eq([1, 1, 1, 1])
      end
    end

    context 'with no overlap' do
      it 'returns an empty array' do
        result = generator.find_matches([1, 2], [3, 4])
        expect(result).to eq([])
      end
    end

    context 'with empty lists' do
      it 'returns an empty array when list_a is empty' do
        result = generator.find_matches([], [1, 2])
        expect(result).to eq([])
      end

      it 'returns an empty array when list_b is empty' do
        result = generator.find_matches([1, 2], [])
        expect(result).to eq([])
      end
    end

    context 'with nil inputs' do
      it 'raises an error when list_a is nil' do
        expect do
          generator.find_matches(nil, [1])
        end.to raise_error(NoMethodError)
      end

      it 'raises an error when list_b is nil' do
        expect do
          generator.find_matches([1], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    let(:generator) do
      described_class.new
    end

    before do
      stub_const('User', Class.new)
    end

    context 'when users exist' do
      let(:user1) do
        double('User1')
      end

      let(:user2) do
        double('User2')
      end

      before do
        allow(User).to receive(:all).and_return([user1, user2])
        allow(generator).to receive(:send_email)
      end

      it 'calls send_email for each user' do
        expect(generator).to receive(:send_email).with(user1).once
        expect(generator).to receive(:send_email).with(user2).once
        generator.process_all_users
      end
    end

    context 'when there are no users' do
      before do
        allow(User).to receive(:all).and_return([])
      end

      it 'does not call send_email' do
        expect(generator).not_to receive(:send_email)
        generator.process_all_users
      end
    end

    context 'when send_email raises an error' do
      let(:user1) do
        double('User1')
      end

      let(:user2) do
        double('User2')
      end

      before do
        allow(User).to receive(:all).and_return([user1, user2])
        allow(generator).to receive(:send_email) do |user|
          raise 'boom' if user == user1
        end
      end

      it 'propagates the error' do
        expect do
          generator.process_all_users
        end.to raise_error(RuntimeError, 'boom')
      end
    end

    context 'when User.all raises an error' do
      before do
        allow(User).to receive(:all).and_raise(StandardError, 'db down')
      end

      it 'propagates the error' do
        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'db down')
      end
    end

    context 'when User.all returns nil' do
      before do
        allow(User).to receive(:all).and_return(nil)
      end

      it 'raises an error when iterating over nil' do
        expect do
          generator.process_all_users
        end.to raise_error(NoMethodError)
      end
    end
  end
end
