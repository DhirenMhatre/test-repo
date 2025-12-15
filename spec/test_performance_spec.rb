require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  subject(:generator) do
    described_class.new
  end

  before do
    stub_const('User', Class.new)
  end

  describe '#generate_user_report' do
    let(:user_ids) do
      [1, 2]
    end

    let(:user1) do
      double('User', name: 'Alice')
    end

    let(:user2) do
      double('User', name: 'Bob')
    end

    let(:posts1) do
      double('Posts', count: 3)
    end

    let(:posts2) do
      double('Posts', count: 5)
    end

    before do
      allow(user1).to receive(:posts).and_return(posts1)
      allow(user2).to receive(:posts).and_return(posts2)
      allow(User).to receive(:find).with(1).and_return(user1)
      allow(User).to receive(:find).with(2).and_return(user2)
    end

    context 'with valid user ids' do
      it 'prints each user name and post count to stdout' do
        expect do
          generator.generate_user_report(user_ids)
        end.to output("Alice: 3 posts\nBob: 5 posts\n").to_stdout
      end

      it 'queries the database for each user id' do
        expect do
          generator.generate_user_report(user_ids)
        end.to output.to_stdout
        expect(User).to have_received(:find).with(1).once
        expect(User).to have_received(:find).with(2).once
        expect(user1).to have_received(:posts).once
        expect(user2).to have_received(:posts).once
      end
    end

    context 'with an empty array' do
      let(:user_ids) do
        []
      end

      before do
        allow(User).to receive(:find)
      end

      it 'does not print anything' do
        expect do
          generator.generate_user_report(user_ids)
        end.to output('').to_stdout
      end

      it 'does not attempt to query any users' do
        generator.generate_user_report(user_ids)
        expect(User).not_to have_received(:find)
      end
    end

    context 'with nil input' do
      it 'raises a NoMethodError' do
        expect do
          generator.generate_user_report(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    let(:record1) do
      double('Record', id: 1, name: 'Foo')
    end

    let(:record2) do
      double('Record', id: 2, name: 'Bar')
    end

    context 'with valid records' do
      let(:records) do
        [record1, record2]
      end

      it 'returns a CSV string with one line per record' do
        result = generator.build_csv(records)
        expect(result).to eq("1,Foo\n2,Bar\n")
      end
    end

    context 'with an empty array' do
      it 'returns an empty string' do
        result = generator.build_csv([])
        expect(result).to eq('')
      end
    end

    context 'with nil values in records' do
      let(:record3) do
        double('Record', id: nil, name: nil)
      end

      it 'interpolates nil as empty strings' do
        result = generator.build_csv([record3])
        expect(result).to eq(",\n")
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
    context 'with overlapping lists' do
      it 'returns items present in both lists' do
        result = generator.find_matches([1, 2, 3], [2, 3, 4])
        expect(result).to eq([2, 3])
      end
    end

    context 'with duplicates in the second list' do
      it 'includes duplicates for each match found' do
        result = generator.find_matches([2], [2, 2, 3])
        expect(result).to eq([2, 2])
      end
    end

    context 'with no overlap' do
      it 'returns an empty array' do
        result = generator.find_matches([1, 5], [2, 3, 4])
        expect(result).to eq([])
      end
    end

    context 'with empty lists' do
      it 'returns an empty array' do
        result = generator.find_matches([], [])
        expect(result).to eq([])
      end
    end

    context 'with nil inputs' do
      it 'raises a NoMethodError when list_a is nil' do
        expect do
          generator.find_matches(nil, [1, 2])
        end.to raise_error(NoMethodError)
      end

      it 'raises a NoMethodError when list_b is nil' do
        expect do
          generator.find_matches([1, 2], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    let(:user1) do
      double('User', id: 1, email: 'a@example.com')
    end

    let(:user2) do
      double('User', id: 2, email: 'b@example.com')
    end

    before do
      allow(User).to receive(:all).and_return([user1, user2])
      allow(User).to receive(:find_each)
      allow(generator).to receive(:send_email)
    end

    it 'retrieves all users using User.all and iterates through them' do
      expect(User).to receive(:all).and_return([user1, user2])
      expect(User).not_to receive(:find_each)
      generator.process_all_users
    end

    it 'calls send_email for each user' do
      generator.process_all_users
      expect(generator).to have_received(:send_email).with(user1).once
      expect(generator).to have_received(:send_email).with(user2).once
    end

    context 'when there are no users' do
      before do
        allow(User).to receive(:all).and_return([])
      end

      it 'does not call send_email' do
        generator.process_all_users
        expect(generator).not_to have_received(:send_email)
      end
    end

    context 'when sending email fails' do
      before do
        allow(generator).to receive(:send_email).with(user1).and_raise(StandardError, 'boom')
        allow(generator).to receive(:send_email).with(user2)
      end

      it 'propagates the error and stops processing' do
        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'boom')
        expect(generator).to have_received(:send_email).with(user1)
      end
    end
  end
end
