require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  let(:generator) do
    described_class.new
  end

  describe '#generate_user_report' do
    context 'with valid user_ids' do
      let(:user1) do
        instance_double('UserRecord', name: 'Alice', posts: instance_double('Posts', count: 2))
      end

      let(:user2) do
        instance_double('UserRecord', name: 'Bob', posts: instance_double('Posts', count: 3))
      end

      before do
        stub_const('User', Class.new)
        allow(User).to receive(:find).with(1).and_return(user1)
        allow(User).to receive(:find).with(2).and_return(user2)
      end

      it 'queries each user and prints their post count' do
        expect do
          generator.generate_user_report([1, 2])
        end.to output("Alice: 2 posts\nBob: 3 posts\n").to_stdout
      end

      it 'returns nil' do
        result = generator.generate_user_report([1, 2])
        expect(result).to be_nil
      end
    end

    context 'when user_ids is empty' do
      before do
        stub_const('User', Class.new)
      end

      it 'prints nothing' do
        expect do
          generator.generate_user_report([])
        end.to output('').to_stdout
      end

      it 'returns nil' do
        result = generator.generate_user_report([])
        expect(result).to be_nil
      end
    end

    context 'when user lookup raises an error' do
      before do
        stub_const('User', Class.new)
        allow(User).to receive(:find).with(1).and_raise('not found')
      end

      it 'propagates the error' do
        expect do
          generator.generate_user_report([1])
        end.to raise_error(RuntimeError, 'not found')
      end
    end

    context 'with nil input' do
      it 'raises NoMethodError' do
        expect do
          generator.generate_user_report(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    context 'with valid records' do
      let(:records) do
        [
          instance_double('Record', id: 1, name: 'Alice'),
          instance_double('Record', id: 2, name: 'Bob')
        ]
      end

      it 'concatenates records into CSV lines' do
        csv = generator.build_csv(records)
        expect(csv).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with empty records' do
      it 'returns an empty string' do
        csv = generator.build_csv([])
        expect(csv).to eq('')
      end
    end

    context 'with nil records' do
      it 'raises NoMethodError' do
        expect do
          generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    context 'with overlapping arrays' do
      it 'returns elements present in both arrays' do
        matches = generator.find_matches([1, 2, 3], [2, 3, 4])
        expect(matches).to eq([2, 3])
      end
    end

    context 'with duplicates in list_b' do
      it 'includes duplicates for each matching occurrence' do
        matches = generator.find_matches([2], [2, 2, 3])
        expect(matches).to eq([2, 2])
      end
    end

    context 'with no overlap' do
      it 'returns an empty array' do
        matches = generator.find_matches([1, 5], [2, 3, 4])
        expect(matches).to eq([])
      end
    end

    context 'with empty lists' do
      it 'returns an empty array' do
        matches = generator.find_matches([], [])
        expect(matches).to eq([])
      end
    end

    context 'with nil inputs' do
      it 'raises NoMethodError for nil list_a' do
        expect do
          generator.find_matches(nil, [])
        end.to raise_error(NoMethodError)
      end

      it 'raises NoMethodError for nil list_b' do
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

    context 'with users present' do
      let(:users) do
        [
          instance_double('UserRecord', id: 1),
          instance_double('UserRecord', id: 2),
          instance_double('UserRecord', id: 3)
        ]
      end

      before do
        allow(User).to receive(:all).and_return(users)
        allow(generator).to receive(:send_email)
      end

      it 'calls send_email for each user' do
        generator.process_all_users
        expect(generator).to have_received(:send_email).with(users[0])
        expect(generator).to have_received(:send_email).with(users[1])
        expect(generator).to have_received(:send_email).with(users[2])
        expect(generator).to have_received(:send_email).exactly(3).times
      end
    end

    context 'with no users' do
      before do
        allow(User).to receive(:all).and_return([])
        allow(generator).to receive(:send_email)
      end

      it 'does not call send_email' do
        generator.process_all_users
        expect(generator).not_to have_received(:send_email)
      end
    end

    context 'when send_email raises an error' do
      let(:users) do
        [instance_double('UserRecord', id: 1)]
      end

      before do
        allow(User).to receive(:all).and_return(users)
        allow(generator).to receive(:send_email).and_raise('delivery failed')
      end

      it 'propagates the error' do
        expect do
          generator.process_all_users
        end.to raise_error(RuntimeError, 'delivery failed')
      end
    end
  end
end
