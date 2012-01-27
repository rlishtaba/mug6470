require 'open3'

# A trial is a particular configuration of input data, classifier, and training
# and testing modes.
class Trial < ActiveRecord::Base
  serialize :output, Hash
  serialize :selected_features, Array
    
  # The project this trial belongs to.
  belongs_to :project, :inverse_of => :trials
  validates :project, :presence => true

  # The classifier the user chose for this trial.
  belongs_to :classifier
  validates :classifier, :presence => true
    
  # The input data the user chose for this trial.
  belongs_to :datum
  validates :datum, :presence => true

  belongs_to :test_datum, :class_name => :Datum
  validates :test_datum, :presence => { :if => :test_mode? }
  
  # Name of the trial. 
  validates :name, :length => 0..32, :presence => true 

  # The output of this trial.  
  validates :output, :length => 0..32.kilobytes, :presence => true 
 
  # An array of integer indices as selected features used in training. It does
  # not include the class feature which should always be included.
  validates :selected_features, :length => 0..128, :presence => true
  
  validates :mode, :length => 1..32
  
  def test_mode?
    mode == 'test'
  end

  # Executes the trial and returns the result and error.
  #
  # Example command for filtering attributes:
  # java -cp weka.jar weka.classifiers.meta.FilteredClassifier -t data/cpu.arff 
  #     -F "weka.filters.unsupervised.attribute.Remove -R 6" 
  #     -W weka.classifiers.rules.DecisionTable -- 
  #         -X 1 -S "weka.attributeSelection.BestFirst -D 1 -N 5"
  #
  # @return [Hash] result and error from the execution, or nil if datum or 
  #     classifier or selected_features is not specified.
  def run
    self.output = { :result => {}, :error => {} }
    if datum && classifier && selected_features && mode
      classpath = ConfigVar[:weka_classpath]
      data_file = File.join ConfigVar[:data_dir], datum.file_name
      rm_features = (0..datum.num_features - 2).to_a - selected_features
      rm_features_str = rm_features.map { |i| i + 1 }.join ','
      command = ["java -cp #{classpath}",
                 "weka.classifiers.meta.FilteredClassifier", 
                 "-F \"weka.filters.unsupervised.attribute.Remove",
                 "-R #{rm_features_str}\"",
                 "-W #{classifier.program_name} -t #{data_file} -p 1"]

      if test_mode?
        test_data_file = File.join ConfigVar[:data_dir], test_datum.file_name
        command << "-T #{test_data_file}"  
      end
      
      stdin, stdout, stderr = Open3.popen3 command.join ' '
      
      # Only output accuracy and confusion matrix if the class type is nominal
      if datum.nominal_class_type?
        num_class_values = datum.class_values.size 
        matrix = Array.new(num_class_values) { 
              Array.new(num_class_values) { [] } }
        regex = /^\s*\d+\s+(?<actual>\d+):(?<actual_label>[^\s]+)\s+(?<predicted>\d+):[^\s]+\s+\+?\s+(?<confidence>[\d\.]+)\s*\((?<id>\d+)\)/ 
        num_correct = 0
        stdout.readlines.each do |l|
          if md = regex.match(l) 
            id = md[:id].to_i
            actual = md[:actual_label] == '?' ? -1 : md[:actual].to_i 
            predicted = md[:predicted].to_i
            confidence = md[:confidence].to_f
            
            self.output[:result][id] = { :actual => actual,
                :predicted => predicted, :confidence => confidence }
            if actual > 0
              matrix[actual - 1][predicted - 1] << id 
              num_correct += 1 if actual == predicted
            end
          end
        end
        self.output[:result][:confusion_matrix] = matrix
        self.output[:result][:accuracy] = 
            num_correct.to_f / datum.num_examples if datum.num_examples > 0
      end
      
      stderr.readlines.each do |line|
        next if line.strip!.blank?
        if md = /Warning:(?<warning>.+)/i.match(line)
          self.output[:error][:warning] = md[:warning]
        else
          self.output[:error][:error] = line 
        end
        break 
      end
    end 
  end
end
