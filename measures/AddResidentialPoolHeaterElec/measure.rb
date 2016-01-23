require "#{File.dirname(__FILE__)}/resources/schedules"
require "#{File.dirname(__FILE__)}/resources/constants"
require "#{File.dirname(__FILE__)}/resources/util"

#start the measure
class ResidentialPoolHeater < OpenStudio::Ruleset::ModelUserScript
  
  def name
    return "Set Residential Pool Electric Heater"
  end
  
  def description
    return "Adds (or replaces) a residential pool heater with the specified efficiency and schedule. The pool is assumed to be outdoors."
  end
  
  def modeler_description
    return "Since there is no Pool Heater object in OpenStudio/EnergyPlus, we look for an ElectricEquipment or GasEquipment object with the name that denotes it is a residential pool heater. If one is found, it is replaced with the specified properties. Otherwise, a new such object is added to the model. Note: This measure requires HVAC equipment to have already been assigned so that the building conditioned floor area (CFA) can be calculated. This measure also requires the number of bedrooms/bathrooms to have already been assigned."
  end
  
  #define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Ruleset::OSArgumentVector.new
    
	#TODO: New argument for demand response for pool heaters (alternate schedules if automatic DR control is specified)
	
	#make a double argument for Base Energy Use
	base_energy = OpenStudio::Ruleset::OSArgument::makeDoubleArgument("base_energy")
	base_energy.setDisplayName("Base Energy Use")
    base_energy.setUnits("kWh/yr")
	base_energy.setDescription("The national average (Building America Benchmark) energy use.")
	base_energy.setDefaultValue(2300)
	args << base_energy

	#make a double argument for Energy Multiplier
	mult = OpenStudio::Ruleset::OSArgument::makeDoubleArgument("mult")
	mult.setDisplayName("Energy Multiplier")
	mult.setDescription("Sets the annual energy use equal to the base energy use times this multiplier.")
	mult.setDefaultValue(1)
	args << mult
	
    #make a boolean argument for Scale Energy Use
	scale_energy = OpenStudio::Ruleset::OSArgument::makeBoolArgument("scale_energy",true)
	scale_energy.setDisplayName("Scale Energy Use")
	scale_energy.setDescription("If true, scales the energy use relative to a 3-bedroom, 1920 sqft house using the following equation: Fscale = (0.5 + 0.25 x Nbr/3 + 0.25 x FFA/1920) where Nbr is the number of bedrooms and FFA is the finished floor area.")
	scale_energy.setDefaultValue(true)
	args << scale_energy

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
    base_energy = runner.getDoubleArgumentValue("base_energy",user_arguments)
	mult = runner.getDoubleArgumentValue("mult",user_arguments)
    scale_energy = runner.getBoolArgumentValue("scale_energy",user_arguments)
	weekday_sch = runner.getStringArgumentValue("weekday_sch",user_arguments)
	weekend_sch = runner.getStringArgumentValue("weekend_sch",user_arguments)
	monthly_sch = runner.getStringArgumentValue("monthly_sch",user_arguments)
    
    #check for valid inputs
    if base_energy < 0
		runner.registerError("Base energy use must be greater than or equal to 0.")
		return false
    end
    if mult < 0
		runner.registerError("Energy multiplier must be greater than or equal to 0.")
		return false
    end
    
    # Get CFA and number of bedrooms/bathrooms
    cfa = HelperMethods.get_building_conditioned_floor_area(model, runner)
    if cfa.nil?
        return false
    end
    nbeds, nbaths = HelperMethods.get_bedrooms_bathrooms(model, runner)
    if nbeds.nil? or nbaths.nil?
        return false
    end
    
	#Calculate annual energy use
    ann_elec = base_energy * mult # kWh/yr

    if scale_energy
        #Scale energy use by num beds and floor area
        constant = ann_elec/2
        nbr_coef = ann_elec/4/3
        cfa_coef = ann_elec/4/1920
        ph_ann = constant + nbr_coef * nbeds + cfa_coef * cfa # kWh/yr
    else
        ph_ann = ann_elec # kWh/yr
    end

    #hard coded convective, radiative, latent, and lost fractions
    ph_lat = 0
    ph_rad = 0
    ph_conv = 0
    ph_lost = 1 - ph_lat - ph_rad - ph_conv
	
	obj_name = Constants.ObjectNamePoolHeater
	obj_name_e = obj_name + "_" + Constants.FuelTypeElectric
	obj_name_g = obj_name + "_" + Constants.FuelTypeGas
	sch = MonthHourSchedule.new(weekday_sch, weekend_sch, monthly_sch, model, obj_name_e, runner)
	if not sch.validated?
		return false
	end
	design_level = sch.calcDesignLevelFromDailykWh(ph_ann/365.0)
	
	#add pool heater to an arbitrary space (there are no space gains)
	has_elec_ph = 0
	replace_elec_ph = 0
    replace_g_ph = 0
    space = HelperMethods.get_default_space(model, runner)
    if space.nil?
        return false
    end
    space_equipments_g = space.gasEquipment
    space_equipments_g.each do |space_equipment_g| #check for an existing gas range
        if space_equipment_g.gasEquipmentDefinition.name.get.to_s == obj_name_g
            runner.registerInfo("There is already a pool gas heater. The existing pool gas heater will be replaced with the specified pool electric heater.")
            space_equipment_g.remove
            replace_g_ph = 1
        end
    end
    space_equipments = space.electricEquipment
    space_equipments.each do |space_equipment|
        if space_equipment.electricEquipmentDefinition.name.get.to_s == obj_name_e
            has_elec_ph = 1
            runner.registerInfo("There is already a pool electric heater. The existing pool electric heater will be replaced with the specified pool electric heater.")
            space_equipment.electricEquipmentDefinition.setDesignLevel(design_level)
            sch.setSchedule(space_equipment)
            replace_elec_ph = 1
        end
    end
    if has_elec_ph == 0 
        has_elec_ph = 1
        
        #Add electric equipment for the pool heater
        ph_def = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
        ph = OpenStudio::Model::ElectricEquipment.new(ph_def)
        ph.setName(obj_name_e)
        ph.setSpace(space)
        ph_def.setName(obj_name_e)
        ph_def.setDesignLevel(design_level)
        ph_def.setFractionRadiant(ph_rad)
        ph_def.setFractionLatent(ph_lat)
        ph_def.setFractionLost(ph_lost)
        sch.setSchedule(ph)
        
    end
	
    #reporting final condition of model
    runner.registerFinalCondition("A pool electric heater has been set with #{ph_ann.round} kWhs annual energy consumption.")
	
    return true
 
  end #end the run method

end #end the measure

#this allows the measure to be use by the application
ResidentialPoolHeater.new.registerWithApplication