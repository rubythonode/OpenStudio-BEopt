require "#{File.dirname(__FILE__)}/resources/schedules"
require "#{File.dirname(__FILE__)}/resources/constants"
require "#{File.dirname(__FILE__)}/resources/util"

#start the measure
class ResidentialPoolHeater < OpenStudio::Ruleset::ModelUserScript
  
  def name
    return "Add/Replace Residential Gas Pool Heater"
  end
  
  def description
    return "Adds (or replaces) a residential gas pool heater with the specified efficiency and schedule. The pool is assumed to be outdoors."
  end
  
  def modeler_description
    return "Since there is no Gas Pool Heater object in OpenStudio/EnergyPlus, we look for a GasEquipment object with the name that denotes it is a residential gas pool heater. If one is found, it is replaced with the specified properties. Otherwise, a new such object is added to the model."
  end
  
  #define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Ruleset::OSArgumentVector.new
    
	#TODO: New argument for demand response for pool heaters (alternate schedules if automatic DR control is specified)
	
	#make a double argument for Energy Multiplier
	mult = OpenStudio::Ruleset::OSArgument::makeDoubleArgument("mult")
	mult.setDisplayName("Energy Multiplier")
	mult.setDescription("Sets the annual energy use equal to the national average (Building America Benchmark) energy use times this multiplier.")
	mult.setDefaultValue(1)
	args << mult
	
	#Make a string argument for 24 weekday schedule values
	weekday_sch = OpenStudio::Ruleset::OSArgument::makeStringArgument("weekday_sch")
	weekday_sch.setDisplayName("Weekday schedule")
	weekday_sch.setDescription("Specify the 24-hour weekday schedule.")
	weekday_sch.setDefaultValue("0.003, 0.003, 0.003, 0.004, 0.008, 0.015, 0.026, 0.044, 0.084, 0.121, 0.127, 0.121, 0.120, 0.090, 0.075, 0.061, 0.037, 0.023, 0.013, 0.008, 0.004, 0.003, 0.003, 0.003")
	args << weekday_sch
    
	#Make a string argument for 24 weekend schedule values
	weekend_sch = OpenStudio::Ruleset::OSArgument::makeStringArgument("weekend_sch")
	weekend_sch.setDisplayName("Weekend schedule")
	weekend_sch.setDescription("Specify the 24-hour weekend schedule.")
	weekend_sch.setDefaultValue("0.003, 0.003, 0.003, 0.004, 0.008, 0.015, 0.026, 0.044, 0.084, 0.121, 0.127, 0.121, 0.120, 0.090, 0.075, 0.061, 0.037, 0.023, 0.013, 0.008, 0.004, 0.003, 0.003, 0.003")
	args << weekend_sch

	#Make a string argument for 12 monthly schedule values
	monthly_sch = OpenStudio::Ruleset::OSArgument::makeStringArgument("monthly_sch")
	monthly_sch.setDisplayName("Month schedule")
	monthly_sch.setDescription("Specify the 12-month schedule.")
	monthly_sch.setDefaultValue("1.154, 1.161, 1.013, 1.010, 1.013, 0.888, 0.883, 0.883, 0.888, 0.978, 0.974, 1.154")
	args << monthly_sch

    #make a choice argument for living space type
    space_types = model.getSpaceTypes
    space_type_args = OpenStudio::StringVector.new
    space_types.each do |space_type|
        space_type_args << space_type.name.to_s
    end
    if not space_type_args.include?(Constants.LivingSpaceType)
        space_type_args << Constants.LivingSpaceType
    end
    living_space_type = OpenStudio::Ruleset::OSArgument::makeChoiceArgument("living_space_type", space_type_args, true)
    living_space_type.setDisplayName("Living space type")
    living_space_type.setDescription("Select the living space type. The pool will be located outdoors, but the living space floor area is needed to scale energy use.")
    living_space_type.setDefaultValue(Constants.LivingSpaceType)
    args << living_space_type

    #make a choice argument for finished basement space type
    space_types = model.getSpaceTypes
    space_type_args = OpenStudio::StringVector.new
    space_types.each do |space_type|
        space_type_args << space_type.name.to_s
    end
    if not space_type_args.include?(Constants.FinishedBasementSpaceType)
        space_type_args << Constants.FinishedBasementSpaceType
    end
    fbasement_space_type = OpenStudio::Ruleset::OSArgument::makeChoiceArgument("fbasement_space_type", space_type_args, true)
    fbasement_space_type.setDisplayName("Finished Basement space type")
    fbasement_space_type.setDescription("Select the finished basement space type. The pool will be located outdoors, but the finished basement space floor area is needed to scale energy use.")
    fbasement_space_type.setDefaultValue(Constants.FinishedBasementSpaceType)
    args << fbasement_space_type

    return args
  end #end the arguments method

  #define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)
    
    #use the built-in error checking 
    if not runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end
	
    #assign the user inputs to variables
	mult = runner.getDoubleArgumentValue("mult",user_arguments)
	weekday_sch = runner.getStringArgumentValue("weekday_sch",user_arguments)
	weekend_sch = runner.getStringArgumentValue("weekend_sch",user_arguments)
	monthly_sch = runner.getStringArgumentValue("monthly_sch",user_arguments)

	# Space type
	living_space_type_r = runner.getStringArgumentValue("living_space_type",user_arguments)
    living_space_type = HelperMethods.get_space_type_from_string(model, living_space_type_r, runner)
    if living_space_type.nil?
        return false
    end
	fbasement_space_type_r = runner.getStringArgumentValue("fbasement_space_type",user_arguments)
    fbasement_space_type = HelperMethods.get_space_type_from_string(model, fbasement_space_type_r, runner, false)

    # Get number of bedrooms/bathrooms
    nbeds, nbaths = HelperMethods.get_bedrooms_bathrooms(model, living_space_type.handle, runner)
    if nbeds.nil? or nbaths.nil?
        return false
    end
    
    cfa_living = HelperMethods.get_floor_area(model, living_space_type.handle, runner)
    cfa_fbasement = 0.0
    if not fbasement_space_type.nil?
        cfa_fbasement = HelperMethods.get_floor_area(model, fbasement_space_type.handle, runner)
    end
    cfa_total = cfa_living + cfa_fbasement

	#Calculate annual energy use
	ann_g = 6506 # kWh/yr, per the 2010 BA Benchmark
    ann_g = ann_g * mult # kWh/yr
    
    #Scale energy use by num beds and floor area
    constant = ann_g/2
    nbr_coef = ann_g/4/3
    cfa_coef = ann_g/4/1920
    ph_ann = constant + nbr_coef * nbeds + cfa_coef * cfa_total # kWh/yr
    ph_ann_g = OpenStudio.convert(ph_ann, "kWh", "therm").get

    #hard coded convective, radiative, latent, and lost fractions
    ph_lat = 0
    ph_rad = 0
    ph_conv = 0
    ph_lost = 1 - ph_lat - ph_rad - ph_conv
	
	obj_name = Constants.ObjectNamePoolHeater
	obj_name_e = obj_name + "_" + Constants.FuelTypeElectric
	obj_name_g = obj_name + "_" + Constants.FuelTypeGas
	sch = MonthHourSchedule.new(weekday_sch, weekend_sch, monthly_sch, model, obj_name_g, runner)
	if not sch.validated?
		return false
	end
	design_level = sch.calcDesignLevelFromDailyTherm(ph_ann_g/365.0)
	
	#add pool heater to the living space
    #because there are no space gains, the choice of space is arbitrary
	has_gas_ph = 0
	replace_gas_ph = 0
    replace_elec_ph = 0
    space_equipments_g = living_space_type.gasEquipment
    space_equipments_g.each do |space_equipment_g| #check for an existing gas heater
        if space_equipment_g.gasEquipmentDefinition.name.get.to_s == obj_name_g
            has_gas_ph = 1
            runner.registerInfo("There is already a gas pool heater. The existing gas pool heater will be replaced with the specified gas pool heater.")
            space_equipment_g.gasEquipmentDefinition.setDesignLevel(design_level)
            sch.setSchedule(space_equipment_g)
            replace_gas_ph = 1
        end
    end
    space_equipments_e = living_space_type.electricEquipment
    space_equipments_e.each do |space_equipment_e|
        if space_equipment_e.electricEquipmentDefinition.name.get.to_s == obj_name_e
            runner.registerInfo("There is already an electric pool heater. The existing heater will be replaced with the specified gas pool heater.")
            space_equipment_e.remove
            replace_elec_ph = 1
        end
    end

    if has_gas_ph == 0 
        has_gas_ph = 1
        
        #Add gas equipment for the pool heater
        ph_def = OpenStudio::Model::GasEquipmentDefinition.new(model)
        ph = OpenStudio::Model::GasEquipment.new(ph_def)
        ph.setName(obj_name_g)
        ph.setSpaceType(living_space_type)
        ph_def.setName(obj_name_g)
        ph_def.setDesignLevel(design_level)
        ph_def.setFractionRadiant(ph_rad)
        ph_def.setFractionLatent(ph_lat)
        ph_def.setFractionLost(ph_lost)
        sch.setSchedule(ph)
        
    end
	
    #reporting final condition of model
    if replace_gas_ph == 1
        runner.registerFinalCondition("The existing gas pool heater has been replaced by one with #{ph_ann_g.round} therms annual energy consumption.")
    elsif replace_elec_ph == 1
        runner.registerFinalCondition("The existing electric pool heater has been replaced by a gas pool heater with #{ph_ann_g.round} therms annual energy consumption.")
    else
        runner.registerFinalCondition("A gas pool heater has been added with #{ph_ann_g.round} therms annual energy consumption.")
    end
	
    return true
 
  end #end the run method

end #end the measure

#this allows the measure to be use by the application
ResidentialPoolHeater.new.registerWithApplication