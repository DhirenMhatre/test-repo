require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  describe '#generate_user_report' do
    let(:instance) { described_class.new }

    context 'with valid user IDs' do
      let(:user_ids) { [1, 2] }
      let(:posts1) { double('Posts1', count: 2) }
      let(:posts2) { double('Posts2', count: 5) }
      let(:user1) { double('User1', name: 'Alice', posts: posts1) }
      let(:user2) { double('User2', name: 'Bob', posts: posts2) }

      before do
        stub_const('User', Class.new)
        allow(User).to receive(:find).with(1).and_return(user1)
        allow(User).to receive(:find).with(2).and_return(user2)
      end

      it 'prints a line per user with post counts and returns the original array' do
        expect do
          result = instance.generate_user_report(user_ids)
          expect(result).to eq(user_ids)
        end.to output("Alice: 2 posts\nBob: 5 posts\n").to_stdout
      end
    end

    context 'with empty user IDs' do
      before do
        stub_const('User', Class.new)
      end

      it 'prints nothing and returns an empty array' do
        expect do
          result = instance.generate_user_report([])
          expect(result).to eq([])
        end.to output("").to_stdout
      end
    end

    context 'when a user is not found' do
      before do
        stub_const('User', Class.new)
        allow(User).to receive(:find).with(99).and_raise(StandardError, 'not found')
      end

      it 'raises an error from User.find' do
        expect do
          instance.generate_user_report([99])
        end.to raise_error(StandardError, /not found/)
      end
    end

    context 'when posts association is nil for a user' do
      before do
        stub_const('User', Class.new)
        allow(User).to receive(:find).with(1).and_return(double('User', name: 'NoPosts', posts: nil))
      end

      it 'raises NoMethodError when calling count on nil' do
        expect do
          instance.generate_user_report([1])
        end.to raise_error(NoMethodError)
      end
    end

    context 'with nil input' do
      before do
        stub_const('User', Class.new)
      end

      it 'raises NoMethodError when iterating over nil' do
        expect do
          instance.generate_user_report(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    let(:instance) { described_class.new }

    context 'with multiple records' do
      let(:record1) { double('Record', id: 1, name: 'Alice') }
      let(:record2) { double('Record', id: 2, name: 'Bob') }

      it 'builds a CSV string with one row per record' do
        result = instance.build_csv([record1, record2])
        expect(result).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with empty records' do
      it 'returns an empty string' do
        result = instance.build_csv([])
        expect(result).to eq("")
      end
    end

    context 'with a record having nil name' do
      let(:record) { double('Record', id: 1, name: nil) }

      it 'includes blank name in the CSV' do
        result = instance.build_csv([record])
        expect(result).to eq("1,\n")
      end
    end

    context 'with nil record in the list' do
      it 'raises NoMethodError' do
        expect do
          instance.build_csv([nil])
        end.to raise_error(NoMethodError)
      end
    end

    context 'with nil input' do
      it 'raises NoMethodError when iterating over nil' do
        expect do
          instance.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    let(:instance) { described_class.new }

    context 'with overlapping items including duplicates' do
      it 'returns matches including duplicates based on list_b occurrences' do
        list_a = [2, 3]
        list_b = [3, 3, 2]
        result = instance.find_matches(list_a, list_b)
        expect(result).to eq([2, 3, 3])
      end
    end

    context 'with no overlap' do
      it 'returns an empty array' do
        result = instance.find_matches([1, 2], [3, 4])
        expect(result).to eq([])
      end
    end

    context 'with empty lists' do
      it 'returns an empty array' do
        result = instance.find_matches([], [])
        expect(result).to eq([])
      end
    end

    context 'with nil elements' do
      it 'matches nil values correctly' do
        result = instance.find_matches([nil, 1], [nil, nil, 2])
        expect(result).to eq([nil, nil])
      end
    end

    context 'with nil for list_a' do
      it 'raises NoMethodError when iterating over nil' do
        expect do
          instance.find_matches(nil, [1, 2])
        end.to raise_error(NoMethodError)
      end
    end

    context 'with nil for list_b' do
      it 'raises NoMethodError when iterating over nil' do
        expect do
          instance.find_matches([1, 2], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    let(:instance) { described_class.new }

    context 'with multiple users' do
      let(:user1) { double('User1') }
      let(:user2) { double('User2') }

      before do
        stub_const('User', Class.new)
        allow(User).to receive(:all).and_return([user1, user2])
        allow(instance).to receive(:send_email)
      end

      it 'sends an email to each user' do
        expect(instance).to receive(:send_email).with(user1).ordered
        expect(instance).to receive(:send_email).with(user2).ordered
        instance.process_all_users
      end
    end

    context 'with no users' do
      before do
        stub_const('User', Class.new)
        allow(User).to receive(:all).and_return([])
      end

      it 'does not attempt to send any emails' do
        expect(instance).not_to receive(:send_email)
        instance.process_all_users
      end
    end

    context 'when send_email raises for a user' do
      let(:user1) { double('User1') }
      let(:user2) { double('User2') }

      before do
        stub_const('User', Class.new)
        allow(User).to receive(:all).and_return([user1, user2])
        allow(instance).to receive(:send_email).with(user1).and_raise(StandardError, 'SMTP error')
        allow(instance).to receive(:send_email).with(user2)
      end

      it 'propagates the error' do
        expect do
          instance.process_all_users
        end.to raise_error(StandardError, /SMTP error/)
      end
    end
  end
end
