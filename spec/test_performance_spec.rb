require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  let(:generator) do
    described_class.new
  end

  describe '#generate_user_report' do
    before do
      stub_const('User', Class.new)
    end

    context 'with valid user_ids' do
      let(:user_ids) do
        [1, 2, 3]
      end

      let(:posts1) do
        double('Posts', count: 2)
      end

      let(:posts2) do
        double('Posts', count: 0)
      end

      let(:posts3) do
        double('Posts', count: 5)
      end

      let(:user1) do
        double('User', id: 1, name: 'Alice', posts: posts1)
      end

      let(:user2) do
        double('User', id: 2, name: 'Bob', posts: posts2)
      end

      let(:user3) do
        double('User', id: 3, name: 'Carol', posts: posts3)
      end

      before do
        allow(User).to receive(:find).with(1).and_return(user1)
        allow(User).to receive(:find).with(2).and_return(user2)
        allow(User).to receive(:find).with(3).and_return(user3)
      end

      it 'prints a line for each user and returns the list of ids' do
        result = nil
        expected_output = "Alice: 2 posts\nBob: 0 posts\nCarol: 5 posts\n"
        expect do
          result = generator.generate_user_report(user_ids)
        end.to output(expected_output).to_stdout
        expect(result).to eq(user_ids)
      end
    end

    context 'with an empty list' do
      it 'prints nothing and returns an empty array' do
        result = nil
        expect do
          result = generator.generate_user_report([])
        end.to output('').to_stdout
        expect(result).to eq([])
      end
    end

    context 'when a user lookup fails' do
      it 'raises an error' do
        allow(User).to receive(:find).and_raise(RuntimeError.new('not found'))
        expect do
          generator.generate_user_report([1])
        end.to raise_error(RuntimeError, 'not found')
      end
    end
  end

  describe '#build_csv' do
    let(:record_struct) do
      Struct.new(:id, :name)
    end

    context 'with multiple records' do
      let(:records) do
        [
          record_struct.new(1, 'Alice'),
          record_struct.new(2, 'Bob')
        ]
      end

      it 'concatenates id and name into CSV lines' do
        csv = generator.build_csv(records)
        expect(csv).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with an empty array' do
      it 'returns an empty string' do
        csv = generator.build_csv([])
        expect(csv).to eq('')
      end
    end

    context 'with nil input' do
      it 'raises a NoMethodError' do
        expect do
          generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    context 'when there are overlaps and duplicates' do
      it 'returns all matches including duplicates' do
        list_a = [1, 1, 2]
        list_b = [1, 2, 2]
        result = generator.find_matches(list_a, list_b)
        expect(result).to eq([1, 1, 2, 2])
      end
    end

    context 'when there are no overlaps' do
      it 'returns an empty array' do
        result = generator.find_matches(%w[a b], %w[c d])
        expect(result).to eq([])
      end
    end

    context 'with nil inputs' do
      it 'raises a NoMethodError' do
        expect do
          generator.find_matches(nil, [])
        end.to raise_error(NoMethodError)
        expect do
          generator.find_matches([], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    before do
      stub_const('User', Class.new)
    end

    context 'when users exist' do
      let(:user1) do
        double('User', id: 1)
      end

      let(:user2) do
        double('User', id: 2)
      end

      before do
        allow(User).to receive(:all).and_return([user1, user2])
      end

      it 'sends an email to each user and returns the enumerable' do
        expect(generator).to receive(:send_email).with(user1)
        expect(generator).to receive(:send_email).with(user2)
        result = generator.process_all_users
        expect(result).to eq([user1, user2])
      end
    end

    context 'when there are no users' do
      before do
        allow(User).to receive(:all).and_return([])
      end

      it 'does not send any emails and returns an empty enumerable' do
        expect(generator).not_to receive(:send_email)
        result = generator.process_all_users
        expect(result).to eq([])
      end
    end

    context 'when send_email fails for a user' do
      let(:user1) do
        double('User', id: 1)
      end

      let(:user2) do
        double('User', id: 2)
      end

      before do
        allow(User).to receive(:all).and_return([user1, user2])
      end

      it 'propagates the error and stops processing' do
        expect(generator).to receive(:send_email).with(user1).and_raise(RuntimeError.new('boom'))
        expect(generator).not_to receive(:send_email).with(user2)
        expect do
          generator.process_all_users
        end.to raise_error(RuntimeError, 'boom')
      end
    end
  end
end
