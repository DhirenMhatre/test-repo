require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  before do
    stub_const('User', Class.new)
  end

  describe '#generate_user_report' do
    subject(:generator) { described_class.new }

    context 'with valid user_ids' do
      let(:posts1) { double('Posts') }
      let(:posts2) { double('Posts') }
      let(:user1) { double('User', name: 'Alice', posts: posts1) }
      let(:user2) { double('User', name: 'Bob', posts: posts2) }

      before do
        allow(User).to receive(:find).with(1).and_return(user1)
        allow(User).to receive(:find).with(2).and_return(user2)
        allow(posts1).to receive(:count).and_return(3)
        allow(posts2).to receive(:count).and_return(0)
      end

      it 'queries each user and outputs their posts count' do
        expect(User).to receive(:find).with(1).and_return(user1)
        expect(User).to receive(:find).with(2).and_return(user2)
        expect(posts1).to receive(:count).and_return(3)
        expect(posts2).to receive(:count).and_return(0)
        expect do
          generator.generate_user_report([1, 2])
        end.to output("Alice: 3 posts\nBob: 0 posts\n").to_stdout
      end
    end

    context 'with empty user_ids' do
      it 'does not query and prints nothing' do
        expect(User).not_to receive(:find)
        expect do
          generator.generate_user_report([])
        end.to output('').to_stdout
      end
    end

    context 'when a lookup raises an error' do
      it 'propagates the error' do
        allow(User).to receive(:find).with(42).and_raise(StandardError.new('DB error'))
        expect do
          generator.generate_user_report([42])
        end.to raise_error(StandardError, 'DB error')
      end
    end

    context 'when posts association is nil' do
      it 'raises a NoMethodError for count' do
        user = double('User', name: 'X', posts: nil)
        allow(User).to receive(:find).with(1).and_return(user)
        expect do
          generator.generate_user_report([1])
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    subject(:generator) { described_class.new }

    let(:record_struct) { Struct.new(:id, :name) }

    context 'with multiple records' do
      let(:records) do
        [
          record_struct.new(1, 'Jane'),
          record_struct.new(2, 'Doe')
        ]
      end

      it 'returns a CSV-like string using concatenation' do
        result = generator.build_csv(records)
        expect(result).to eq("1,Jane\n2,Doe\n")
      end
    end

    context 'with empty records' do
      it 'returns an empty string' do
        expect(generator.build_csv([])).to eq('')
      end
    end

    context 'with nil records' do
      it 'raises an error' do
        expect do
          generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when a field is nil' do
      it 'includes empty content for nil field' do
        records = [record_struct.new(2, nil)]
        expect(generator.build_csv(records)).to eq("2,\n")
      end
    end
  end

  describe '#find_matches' do
    subject(:generator) { described_class.new }

    context 'with overlapping elements' do
      it 'returns duplicates for each match in list_b' do
        list_a = [1, 2, 3]
        list_b = [2, 2, 3, 4]
        expect(generator.find_matches(list_a, list_b)).to eq([2, 2, 3])
      end
    end

    context 'with no overlap' do
      it 'returns an empty array' do
        expect(generator.find_matches([1, 5], [2, 3, 4])).to eq([])
      end
    end

    context 'when list_a is empty' do
      it 'returns an empty array' do
        expect(generator.find_matches([], [1, 2, 3])).to eq([])
      end
    end

    context 'when list_b is nil' do
      it 'raises an error' do
        expect do
          generator.find_matches([1, 2], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    subject(:generator) { described_class.new }

    context 'with users present' do
      let(:user1) { double('User1') }
      let(:user2) { double('User2') }

      before do
        allow(User).to receive(:all).and_return([user1, user2])
      end

      it 'sends an email to each user' do
        expect(generator).to receive(:send_email).with(user1).ordered
        expect(generator).to receive(:send_email).with(user2).ordered
        generator.process_all_users
      end
    end

    context 'with no users' do
      before do
        allow(User).to receive(:all).and_return([])
      end

      it 'does not call send_email' do
        expect(generator).not_to receive(:send_email)
        generator.process_all_users
      end
    end

    context 'when fetching users fails' do
      it 'propagates the error' do
        allow(User).to receive(:all).and_raise(StandardError.new('DB down'))
        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'DB down')
      end
    end

    context 'when sending email fails for a user' do
      let(:user1) { double('User1') }
      let(:user2) { double('User2') }

      before do
        allow(User).to receive(:all).and_return([user1, user2])
      end

      it 'propagates the error after processing prior users' do
        expect(generator).to receive(:send_email).with(user1).ordered
        expect(generator).to receive(:send_email).with(user2).and_raise(StandardError.new('SMTP error'))
        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'SMTP error')
      end
    end
  end
end
