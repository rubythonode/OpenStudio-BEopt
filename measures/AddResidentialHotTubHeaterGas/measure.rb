require "#{File.dirname(__FILE__)}/resources/schedules"
require "#{File.dirname(__FILE__)}/resources/constants"
require "#{File.dirname(__FILE__)}/resources/util"

#start the measure
class ResidentialHotTubHeater < OpenStudio::Ruleset::ModelUserScript
  
  def name
    return "Set Residential Hot Tub Gas Heater"
  end
  
  def description
    return "Adds (or replaces) a residential hot tub heater with the specified efficiency and schedule. The hot tub is assumed to be outdoors."
  end
  
  def modeler_description
    return "Since there is no Hot Tub Heater object in OpenStudio/EnergyPlus, we look for a GasEquipment or ElectricEquipment object with the name that denotes it is a residential hot tub heater. If one is found, it is replaced with the specified properties. Otherwise, a new such object is added to the model. Note: This measure requires HVAC equipment to have already been assigned so that the building conditioned floor area (CFA) can be calculated. This measure also requires the number of bedrooms/bathrooms to have already been assigned."
  end
  
  #define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Ruleset::OSArgumentVector.new
    
	#make a double argument for Base Energy Use
	base_energy = OpenStudio::Ruleset::OSArgument::makeDoubleArgument("base_energy")
	base_energy.setDisplayName("Base Energy Use")
    base_energy.setUnits("therm/yr")
	base_energy.setDescription("The national average (Building America Benchmark) energy use.")
	base_energy.setDefaultValue(81)
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
	weekday_sch.setDefaultValue("0.024, 0.029, 0.024, 0.029, 0.047, 0.067, 0.057, 0.024, 0.024, 0.019, 0.015, 0.014, 0.014, 0.014, 0.024, 0.058, 0.126, 0.122, 0.068, 0.061, 0.051, 0.043, 0.024, 0.024")
	args << weekday_sch
    
	#Make a string argument for 24 weekend schedule values
	weekend_sch = OpenStudio::Ruleset::OSArgument::makeStringArgument("weekend_sch")
	weekend_sch.setDisplayName("Weekend schedule")
	weekend_sch.setDescription("Specify the 24-hour weekend schedule.")
	weekend_sch.setDefaultValue("0.024, 0.029, 0.024, 0.029, 0.047, 0.067, 0.057, 0.024, 0.024, 0.019, 0.015, 0.014, 0.014, 0.014, 0.024, 0.058, 0.126, 0.122, 0.068, 0.061, 0.051, 0.043, 0.024, 0.024")
	args << weekend_sch

	#Make a string argument for 12 monthly schedule values
	monthly_sch = OpenStudio::Ruleset::OSArgument::makeStringArgument("monthly_sch")
	monthly_sch.setDisplayName("Month schedule")
	monthly_sch.setDescription("Specify the 12-month schedule.")
	monthly_sch.setDefaultValue("0.837, 0.835, 1.084, 1.084, 1.084, 1.096, 1.096, 1.096, 1.096, 0.931, 0.925, 0.837")
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
    ann_g = base_energy * mult # therm/yr
    
    if scale_energy
        #Scale energy use by num beds and floor area
        constant = ann_g/2
        nbr_coef = ann_g/4/3
        cfa_coef = ann_g/4/1920
        hth_ann_g = constant + nbr_coef * nbeds + cfa_coef * cfa # therm/yr
    else
        hth_ann_g = ann_g # therm/yr
    end

    #hard coded convective, radiative, latent, and lost fractions
    hth_lat = 0
    hth_rad = 0
    hth_conv = 0
    hth_lost = 1 - hth_lat - hth_rad - hth_conv
	
	obj_name = Constants.ObjectNameHotTubHeater
	obj_name_e = obj_name + "_" + Constants.FuelTypeElectric
	obj_name_g = obj_name + "_" + Constants.FuelTypeGas
	sch = MonthHourSchedule.new(weekday_sch, weekend_sch, monthly_sch, model, obj_name_g, runner)
	if not sch.validated?
		return false
	end
	design_level = sch.calcDesignLevelFromDailyTherm(hth_ann_g/365.0)
	
	#add hot tub heater to an arbitrary space (there are no space gains)
	has_gas_hth = 0
	replace_gas_hth = 0
    replace_elec_hth = 0
    space = HelperMethods.get_default_space(model, runner)
    if space.nil?
        return false
    end
    space_equipments_g = space.gasEquipment
    space_equipments_g.each do |space_equipment_g| #check for an existing gas heater
        if space_equipment_g.gasEquipmentDefinition.name.get.to_s == obj_name_g
            has_gas_hth = 1
            runner.registerInfo("There is already a hot tub gas heater. The existing hot tub gas heater will be replaced with the specified hot tub gas heater.")
            space_equipment_g.gasEquipmentDefinition.setDesignLevel(design_level)
            sch.setSchedule(space_equipment_g)
            replace_gas_hth = 1
        end
    end
    space_equipments_e = space.electricEquipment
    space_equipments_e.each do |space_equipment_e|
        if space_equipment_e.electricEquipmentDefinition.name.get.to_s == obj_name_e
            runner.registerInfo("There is already a hot tub electric heater. The existing heater will be replaced with the specified hot tub gas heater.")
            space_equipment_e.remove
            replace_elec_hth = 1
        end
    end

    if has_gas_hth == 0 
        has_gas_hth = 1
        
        #Add gas equipment for the hot tub heater
        hth_def = OpenStudio::Model::GasEquipmentDefinition.new(model)
        hth = OpenStudio::Model::GasEquipment.new(hth_def)
        hth.setName(obj_name_g)
        hth.setSpace(space)
        hth_def.setName(obj_name_g)
        hth_def.setDesignLevel(design_level)
        hth_def.setFractionRadiant(hth_rad)
        hth_def.setFractionLatent(hth_lat)
        hth_def.setFractionLost(hth_lost)
        sch.setSchedule(hth)
        
    end
	
    #reporting final condition of model
    runner.registerFinalCondition("A hot tub gas heater has been set with #{hth_ann_g.round} therms annual energy consumption.")
	
    return true
 
  end #end the run method

end #end the measure

#this allows the measure to be use by the application
ResidentialHotTubHeater.new.registerWithApplication