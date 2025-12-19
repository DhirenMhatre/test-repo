require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  let(:generator) do
    described_class.new
  end

  describe '#generate_user_report' do
    context 'with valid user ids' do
      let(:user1) do
        double('User', name: 'Alice', posts: double('Posts', count: 2))
      end

      let(:user2) do
        double('User', name: 'Bob', posts: double('Posts', count: 3))
      end

      before do
        stub_const('User', Class.new)
        allow(User).to receive(:find).with(1).and_return(user1)
        allow(User).to receive(:find).with(2).and_return(user2)
      end

      it 'queries each user, prints name and post count, and returns the original ids' do
        expect do
          result = generator.generate_user_report([1, 2])
          expect(result).to eq([1, 2])
        end.to output("Alice: 2 posts\nBob: 3 posts\n").to_stdout
        expect(User).to have_received(:find).with(1).once
        expect(User).to have_received(:find).with(2).once
      end
    end

    context 'when user_ids is empty' do
      it 'returns an empty array and prints nothing' do
        expect do
          result = generator.generate_user_report([])
          expect(result).to eq([])
        end.to output('').to_stdout
      end
    end

    context 'when a database lookup raises an error' do
      before do
        stub_const('User', Class.new)
        allow(User).to receive(:find).and_raise(StandardError, 'DB down')
      end

      it 'propagates the error' do
        expect do
          generator.generate_user_report([1])
        end.to raise_error(StandardError, 'DB down')
      end
    end
  end

  describe '#build_csv' do
    let(:record_struct) do
      Struct.new(:id, :name)
    end

    context 'with valid records' do
      let(:records) do
        [
          record_struct.new(1, 'Alice'),
          record_struct.new(2, 'Bob')
        ]
      end

      it 'returns a CSV string with one line per record' do
        csv = generator.build_csv(records)
        expect(csv).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with special characters in fields' do
      let(:records) do
        [
          record_struct.new(1, 'Al,ice'),
          record_struct.new(2, "Bo\nb")
        ]
      end

      it 'concatenates raw values without escaping' do
        csv = generator.build_csv(records)
        expect(csv).to eq("1,Al,ice\n2,Bo\nb\n")
      end
    end

    context 'when records is empty' do
      it 'returns an empty string' do
        csv = generator.build_csv([])
        expect(csv).to eq('')
      end
    end

    context 'when records is nil' do
      it 'raises an error' do
        expect do
          generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    context 'with overlapping elements' do
      it 'returns the common elements' do
        result = generator.find_matches([1, 2, 3], [2, 3, 4])
        expect(result).to eq([2, 3])
      end
    end

    context 'with duplicates in list_b' do
      it 'includes duplicates for each match encountered' do
        result = generator.find_matches([2], [2, 2])
        expect(result).to eq([2, 2])
      end
    end

    context 'with no matches' do
      it 'returns an empty array' do
        result = generator.find_matches([1, 2], [3, 4])
        expect(result).to eq([])
      end
    end

    context 'with empty inputs' do
      it 'returns an empty array when list_a is empty' do
        result = generator.find_matches([], [1, 2])
        expect(result).to eq([])
      end

      it 'returns an empty array when list_b is empty' do
        result = generator.find_matches([1, 2], [])
        expect(result).to eq([])
      end
    end

    context 'when inputs are nil' do
      it 'raises an error for nil list_a' do
        expect do
          generator.find_matches(nil, [1, 2])
        end.to raise_error(NoMethodError)
      end

      it 'raises an error for nil list_b' do
        expect do
          generator.find_matches([1, 2], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    context 'with users present' do
      let(:user1) do
        double('User1')
      end

      let(:user2) do
        double('User2')
      end

      before do
        stub_const('User', Class.new)
        allow(User).to receive(:all).and_return([user1, user2])
        allow(generator).to receive(:send_email)
      end

      it 'calls send_email for each user' do
        generator.process_all_users
        expect(generator).to have_received(:send_email).with(user1).once
        expect(generator).to have_received(:send_email).with(user2).once
      end
    end

    context 'with no users' do
      before do
        stub_const('User', Class.new)
        allow(User).to receive(:all).and_return([])
        allow(generator).to receive(:send_email)
      end

      it 'does not call send_email' do
        generator.process_all_users
        expect(generator).not_to have_received(:send_email)
      end
    end

    context 'when sending email raises an error' do
      let(:user1) do
        double('User1')
      end

      let(:user2) do
        double('User2')
      end

      before do
        stub_const('User', Class.new)
        allow(User).to receive(:all).and_return([user1, user2])
        allow(generator).to receive(:send_email).with(user1).and_return(true)
        allow(generator).to receive(:send_email).with(user2).and_raise(RuntimeError, 'SMTP error')
      end

      it 'propagates the error and may have sent some emails' do
        expect do
          generator.process_all_users
        end.to raise_error(RuntimeError, 'SMTP error')
        expect(generator).to have_received(:send_email).with(user1).once
      end
    end

    context 'when fetching users raises an error' do
      before do
        stub_const('User', Class.new)
        allow(User).to receive(:all).and_raise(StandardError, 'DB error')
      end

      it 'propagates the error' do
        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'DB error')
      end
    end
  end
end
