######################################################################
#  Copyright (c) 2008-2014, Alliance for Sustainable Energy.  
#  All rights reserved.
#  
#  This library is free software; you can redistribute it and/or
#  modify it under the terms of the GNU Lesser General Public
#  License as published by the Free Software Foundation; either
#  version 2.1 of the License, or (at your option) any later version.
#  
#  This library is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#  Lesser General Public License for more details.
#  
#  You should have received a copy of the GNU Lesser General Public
#  License along with this library; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
######################################################################

######################################################################
# == Synopsis 
#
# == Usage
#
#  ruby UserScriptAdapter.rb --userScript=filePath
#
# == Examples
#
######################################################################

require 'openstudio'
require 'optparse'

scriptfolder = File.expand_path(File.dirname(File.dirname(__FILE__)))
originalwd = Dir.pwd()
puts "Script executing from: " + scriptfolder

options = Hash.new
options[:arguments] = []

optparse = OptionParser.new do|opts|

  opts.on('-u','--userScript USERSCRIPT', String, "Path to .rb file that contains an OpenStudio::Ruleset::UserScript" ) do |userScript|
    options[:userScript] = userScript
  end
  
  opts.on('-i','--inputPath INPUTPATH', String, "Path to input model (OpenStudio::Model::Model or OpenStudio::Workspace)." ) do |inputPath|
    options[:inputPath] = inputPath
  end
  
  opts.on('-o','--outputPath OUTPUTPATH', String, "Output file to write (OpenStudio::Model::Model or OpenStudio::Workspace)." ) do |outputPath|
    options[:outputPath] = outputPath
  end
  
  opts.on('-s','--lastOpenStudioModelPath LASTOPENSTUDIOMODELPATH', String, "Path to last OpenStudio Model generated by this workflow." ) do |lastOpenStudioModelPath|
    options[:lastOpenStudioModelPath] = lastOpenStudioModelPath
  end
    
  opts.on('-s','--lastEnergyPlusWorkspacePath LASTENERGYPLUSWORKSPACEPATH', String, "Path to last EnergyPlus Workspace generated by this workflow." ) do |lastEnergyPlusWorkspacePath|
    options[:lastEnergyPlusWorkspacePath] = lastEnergyPlusWorkspacePath
  end
    
  opts.on('-s','--lastEnergyPlusSqlFilePath LASTENERGYPLUSSQLFILEPATH', String, "Path to last EnergyPlus SqlFile generated by this workflow." ) do |lastEnergyPlusSqlFilePath|
    options[:lastEnergyPlusSqlFilePath] = lastEnergyPlusSqlFilePath
  end
  
  opts.on('-s','--lastEpwFilePathArgument LASTEPWFILEPATH', String, "Path to last EpwFile generated by this workflow." ) do |lastEpwFilePath|
    options[:lastEpwFilePath] = lastEpwFilePath
  end
  
  opts.on('-n','--argumentName ARGUMENTNAME', String, "Name of next argument.") do |argumentName|
    options[:tempName] = argumentName
  end
  
  opts.on('-v','--argumentValue ARGUMENTVALUE', String, "Value of next argument.") do |argumentValue|
    puts "Found argument '" + options[:tempName] + "' with value '" + argumentValue + "'."
    argValPair = [options[:tempName].to_s,argumentValue]
    options[:arguments].push(argValPair)
  end
     
end

optparse.parse!

if File.directory?(scriptfolder + "/mergedjob-0")
  # if the 0th job has been merged in, switch to it
  Dir.chdir("#{scriptfolder}/mergedjob-0") 
end

# GET THE USER SCRIPT

if options[:userScript]
  user_script_path = OpenStudio::Path.new(options[:userScript])
else
  user_script_path = OpenStudio::Path.new("./user_script.rb")
end

# Check list of objects in memory before loading the script
currentObjects = Hash.new
ObjectSpace.each_object(OpenStudio::Ruleset::UserScript) { |obj| currentObjects[obj] = true }

ObjectSpace.garbage_collect
load user_script_path.to_s # need load in case have seen this script before

userScript = nil
type = String.new
ObjectSpace.each_object(OpenStudio::Ruleset::UserScript) { |obj|
  if not currentObjects[obj]
    if obj.is_a? OpenStudio::Ruleset::ModelUserScript
      userScript = obj
      type = "model"
    elsif obj.is_a? OpenStudio::Ruleset::WorkspaceUserScript
      userScript = obj
      type = "workspace"
    elsif obj.is_a? OpenStudio::Ruleset::TranslationUserScript
      userScript = obj
      type = "translation"
    elsif obj.is_a? OpenStudio::Ruleset::UtilityUserScript
      userScript = obj
      type = "utility"    
    elsif obj.is_a? OpenStudio::Ruleset::ReportingUserScript
      userScript = obj
      type = "report"    
    end
  end
}

if not userScript
  raise "Unable to locate UserScript class in " + user_script_path.to_s + 
        ", you may need to instantiate the newly defined OpenStudio::Rulset::UserScript class at "
        "the end of the file to enable finding by introspection."
else
  puts "Found UserScript '" + userScript.name + "'."
end

# GET THE INPUT MODEL

input_path = nil
if options[:inputPath]
  input_path = OpenStudio::Path.new(options[:inputPath])
else
  osmDefaultPath = OpenStudio::Path.new("in.osm")  
  idfDefaultPath = OpenStudio::Path.new("in.idf")
  if type == "model"
    input_path = osmDefaultPath
  elsif type == "workspace"
    input_path = idfDefaultPath
  else
    if OpenStudio::exists(osmDefaultPath)
      input_path = osmDefaultPath
    elsif OpenStudio::exists(idfDefaultPath)
      input_path = idfDefaultPath
    end
  end
end

model = OpenStudio::Model::Model.new
workspace = OpenStudio::Workspace.new("Draft".to_StrictnessLevel,"EnergyPlus".to_IddFileType)
input_data = nil
save_model = false
save_workspace = false

if type == "model"

  if not input_path or not OpenStudio::exists(input_path)
    raise "No input file could be located. Was looking for '" + input_path.to_s + "'."
  end
  model = OpenStudio::Model::Model::load(input_path)
  raise "Unable to load OpenStudio Model from '" + input_path.to_s + "'." if model.empty?
  model = model.get
  save_model = true
  input_data = model
  
elsif type == "workspace"

  if not input_path or not OpenStudio::exists(input_path)
    raise "No input file could be located. Was looking for '" + input_path.to_s + "'."
  end
  workspace = OpenStudio::Workspace::load(input_path,"EnergyPlus".to_IddFileType)
  raise "Unable to load OpenStudio Workspace from '" + input_path.to_s + "'." if workspace.empty?
  workspace = workspace.get
  save_workspace = true
  input_data = workspace
  
elsif type == "translation"

  if not input_path or not OpenStudio::exists(input_path)
    raise "No input file could be located. Was looking for '" + input_path.to_s + "'."
  end
  # let file extension determine IDD file type
  workspace = OpenStudio::Workspace::load(input_path)
  raise "Unable to load OpenStudio Workspace from '" + input_path.to_s + "'." if workspace.empty?
  workspace = workspace.get
  if workspace.iddFileType.valueName == "OpenStudio"
    model = OpenStudio::Model::Model.new(workspace)
    workspace = OpenStudio::Workspace("Draft".to_StrictnessLevel,"EnergyPlus".to_IddFileType)
    save_workspace = true
    input_data = model
  else
    save_model = true
    input_data = workspace
  end
  
else

end

##### Begin section to loop for merged user scripts
scriptindex = 0

while (scriptindex == 0 || File.directory?(scriptfolder + "/mergedjob-" + scriptindex.to_s))
  # GET THE ARGUMENTS

  if (scriptindex != 0)
    user_script_path = OpenStudio::Path.new("#{scriptfolder}/mergedjob-#{scriptindex}/user_script.rb")
    
    # The 0th case is already set up, it was the script loaded and parsed up above
    
    # Check list of objects in memory before loading the script
    currentObjects = Hash.new
    ObjectSpace.each_object(OpenStudio::Ruleset::UserScript) { |obj| currentObjects[obj] = true }

    ObjectSpace.garbage_collect
    load user_script_path.to_s # need load in case have seen this script before    

    userScript = nil
    ObjectSpace.each_object(OpenStudio::Ruleset::UserScript) { |obj|
      if not currentObjects[obj]
        if obj.is_a? OpenStudio::Ruleset::ModelUserScript
          userScript = obj
          raise "Mismatched merged script type " unless type == "model"
        elsif obj.is_a? OpenStudio::Ruleset::WorkspaceUserScript
          userScript = obj
          raise "Mismatched merged script type " unless type == "workspace"
        elsif obj.is_a? OpenStudio::Ruleset::TranslationUserScript
          userScript = obj
          raise "Mismatched merged script type " unless type == "translation"
        elsif obj.is_a? OpenStudio::Ruleset::UtilityUserScript
          userScript = obj
          raise "Mismatched merged script type " unless type == "utility"
        elsif obj.is_a? OpenStudio::Ruleset::ReportingUserScript
          userScript = obj
          raise "Mismatched merged script type " unless type == "report"
        end
      end
    }

    if not userScript
      raise "Unable to locate merged UserScript class in " + user_script_path.to_s 
    else
      puts "Found merged UserScript '" + userScript.name + "'."
    end

    options[:arguments] = []

    paramspath = OpenStudio::Path.new("#{scriptfolder}/mergedjob-#{scriptindex}/params.json")
    Dir.chdir("#{scriptfolder}/mergedjob-#{scriptindex}")

    optparse.parse(OpenStudio::Runmanager::RubyJobBuilder.new(paramspath).getScriptParameters())
  end

  userArguments = options[:arguments]
  arguments = OpenStudio::Ruleset::OSArgumentMap.new

  if (input_data)
    userScript.arguments(input_data).each { |arg|
      # look for arg.name() in options
      userArg = nil
      userArguments.each { |candidate|
        if candidate[0] == arg.name
          userArg = candidate
          break
        end
      }
      
      # if found, set
      if userArg
        arg.setValue(userArg[1])
      end
      
      arguments[arg.name] = arg
    }
  else
    userScript.arguments().each { |arg|
      # look for arg.name() in options
      userArg = nil
      userArguments.each { |candidate|
        if candidate[0] == arg.name
          userArg = candidate
          break
        end
      }
      
      # if found, set
      if userArg
        arg.setValue(userArg[1])
      end
      
      arguments[arg.name] = arg
    }
  end

  # RUN SCRIPT WITH DEFAULT RUNNER AND SAVE OUTPUT

  runner = OpenStudio::Ruleset::OSRunner.new

  if lastOpenStudioModelPath = options[:lastOpenStudioModelPath]
    runner.setLastOpenStudioModelPath(OpenStudio::Path.new(lastOpenStudioModelPath))
  end 
    
  if lastEnergyPlusWorkspacePath = options[:lastEnergyPlusWorkspacePath]
    runner.setLastEnergyPlusWorkspacePath(OpenStudio::Path.new(lastEnergyPlusWorkspacePath))
  end

  if lastEnergyPlusSqlFilePath = options[:lastEnergyPlusSqlFilePath]
    runner.setLastEnergyPlusSqlFilePath(OpenStudio::Path.new(lastEnergyPlusSqlFilePath))
  end
  
  if lastEpwFilePath = options[:lastEpwFilePath]
    runner.setLastEpwFilePath(OpenStudio::Path.new(lastEpwFilePath))
  end
  
  result = false
  if type == "model"
    result = userScript.run(model,runner,arguments)
  elsif type == "workspace"
    result = userScript.run(workspace,runner,arguments)
  elsif type == "translation"
    result = userScript.run(workspace,model,runner,arguments)
  elsif type == "utility"
    result = userScript.run(runner,arguments)
  elsif type == "report"
    result = userScript.run(runner,arguments)  
  end

  scriptindex += 1
  # SAVE SCRIPT RESULT

  runner.result.save(OpenStudio::Path.new("result.ossr"),true)
  
  # stop executing scripts once an error is encountered
  break if not result

end

### end looping code

Dir.chdir(originalwd)

puts "Processed 1 base script and #{scriptindex - 1} merged scripts"


# SAVE OUTPUT MODEL

output_path = nil
if options[:outputPath]
  output_path = OpenStudio::Path.new(options[:outputPath])
elsif save_model
  output_path = OpenStudio::Path.new("out.osm")
elsif save_workspace
  output_path = OpenStudio::Path.new("out.idf")
end

if save_model
  model.save(output_path,true)
elsif save_workspace
  workspace.save(output_path,true)
end


# make doubly sure RunManager flags this job as failed
raise "Error encountered. See result.ossr." if not result

