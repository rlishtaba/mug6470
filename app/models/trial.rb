require 'open3'

# A trial is a particular configuration of input data, classifier, and training
# and testing modes.
class Trial < ActiveRecord::Base
  # The classifier the user chose for this trial.
  belongs_to :classifier
  
  # The input data the user chose for this trial.
  belongs_to :datum
 
  # Executes the trial and returns the result and error.
  #
  # @return [Hash] result and error from the execution, or nil if datum or 
  #     classifier is not specified.
  def run
    if datum && classifier
      classpath = ConfigVar[:weka_classpath]
      puts classpath
      data_file = File.join ConfigVar[:data_dir], datum.file_name
      command = "java -cp #{classpath} #{classifier} -t #{data_file} -i"
      stdin, stdout, stderr = Open3.popen3 command
      output = {}
      output[:result] = stdout.readlines
      output[:error] = stderr.readlines
      output
    end 
  end

end