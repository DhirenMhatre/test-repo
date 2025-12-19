require 'spec_helper'

RSpec.describe ReportGenerator do
  subject(:generator) do
    described_class.new
  end

  describe '#generate_user_report' do
    let(:user1) do
      double('User', name: 'Alice', posts: posts1)
    end

    let(:user2) do
      double('User', name: 'Bob', posts: posts2)
    end

    let(:posts1) do
      double('Posts', count: 2)
    end

    let(:posts2) do
      double('Posts', count: 5)
    end

    before do
      stub_const('User', Class.new)
      allow(User).to receive(:find).with(1).and_return(user1)
      allow(User).to receive(:find).with(2).and_return(user2)
    end

    it 'queries each user id and prints name and posts count' do
      expect do
        generator.generate_user_report([1, 2])
      end.to output("Alice: 2 posts\nBob: 5 posts\n").to_stdout
    end

    it 'makes a database call per id' do
      generator.generate_user_report([1, 2])
      expect(User).to have_received(:find).with(1)
      expect(User).to have_received(:find).with(2)
    end

    context 'when list is empty' do
      it 'prints nothing' do
        expect do
          generator.generate_user_report([])
        end.to output('').to_stdout
      end
    end

    context 'when User.find raises' do
      before do
        allow(User).to receive(:find).with(99).and_raise(StandardError.new('not found'))
      end

      it 'propagates the error' do
        expect do
          generator.generate_user_report([99])
        end.to raise_error(StandardError, 'not found')
      end
    end

    context 'when user has no posts method' do
      let(:bad_user) do
        double('User', name: 'NoPosts')
      end

      before do
        allow(User).to receive(:find).with(3).and_return(bad_user)
      end

      it 'raises NoMethodError' do
        expect do
          generator.generate_user_report([3])
        end.to raise_error(NoMethodError)
      end
    end

    context 'when user_ids is nil' do
      it 'raises NoMethodError' do
        expect do
          generator.generate_user_report(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    let(:record1) do
      double('Record', id: 1, name: 'A')
    end

    let(:record2) do
      double('Record', id: 2, name: 'B')
    end

    it 'concatenates csv lines for each record' do
      csv = generator.build_csv([record1, record2])
      expect(csv).to eq("1,A\n2,B\n")
    end

    it 'returns empty string for empty input' do
      csv = generator.build_csv([])
      expect(csv).to eq('')
    end

    it 'raises when a record misses attributes' do
      bad_record = double('Record', id: 10)
      expect do
        generator.build_csv([bad_record])
      end.to raise_error(NoMethodError)
    end

    it 'handles single record' do
      csv = generator.build_csv([record1])
      expect(csv).to eq("1,A\n")
    end
  end

  describe '#find_matches' do
    it 'returns matched values including duplicates for nested loops behavior' do
      result = generator.find_matches([1, 1, 2], [1, 1])
      expect(result).to eq([1, 1, 1, 1])
    end

    it 'returns empty array when no matches' do
      result = generator.find_matches([1, 2], [3, 4])
      expect(result).to eq([])
    end

    it 'returns empty array when either list is empty' do
      expect(generator.find_matches([], [1, 2])).to eq([])
      expect(generator.find_matches([1, 2], [])).to eq([])
    end

    it 'matches strings exactly' do
      result = generator.find_matches(%w[a b], %w[b c])
      expect(result).to eq(['b'])
    end

    it 'raises when list_a is nil' do
      expect do
        generator.find_matches(nil, [1])
      end.to raise_error(NoMethodError)
    end

    it 'raises when list_b is nil' do
      expect do
        generator.find_matches([1], nil)
      end.to raise_error(NoMethodError)
    end
  end

  describe '#process_all_users' do
    let(:user1) do
      double('User')
    end

    let(:user2) do
      double('User')
    end

    before do
      stub_const('User', Class.new)
      allow(User).to receive(:all).and_return([user1, user2])
      allow(generator).to receive(:send_email)
    end

    it 'loads all users and calls send_email for each' do
      generator.process_all_users
      expect(User).to have_received(:all)
      expect(generator).to have_received(:send_email).with(user1)
      expect(generator).to have_received(:send_email).with(user2)
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

    context 'when send_email raises' do
      before do
        allow(User).to receive(:all).and_return([user1, user2])
        allow(generator).to receive(:send_email).with(user1).and_raise(StandardError.new('boom'))
      end

      it 'propagates the error and stops iteration' do
        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'boom')
      end
    end
  end
end
