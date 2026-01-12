# Mod to convert Objects into a Patterns with the saem texture
var script_class = "tool"

var switch_button = null

const COMBINED_DATA_STORE = "UchideshiNodeData"

# Logging Functions
const ENABLE_LOGGING = true
const LOGGING_LEVEL = 0

#########################################################################################################
##
## UTILITY FUNCTIONS
##
#########################################################################################################

func outputlog(msg,level=0):
	if ENABLE_LOGGING:
		if level <= LOGGING_LEVEL:
			printraw("(%d) <ConvertObjectToPattern>: " % OS.get_ticks_msec())
			print(msg)
	else:
		pass

# Function to look at a node and determine what type it is based on its properties
func get_node_type(node):

	outputlog("get_node_type: " + str(node),2)

	if node.get("WallID") != null:
		return "portals"

	# Note this is also true of portals but we caught those with WallID
	elif node.get("Sprite") != null:
		return "objects"
	elif node.get("FadeIn") != null:
		return "paths"
	elif node.get("HasOutline") != null:
		return "pattern_shapes"
	elif node.get("Joint") != null:
		return "walls"

	return null

# Function to get the texture of a node based on tool_type
func get_asset_texture(node, tool_type: String):
	var texture = null

	outputlog("get_asset_texture: node: " + str(node) + " tool_type/type: " + str(tool_type),2)

	match tool_type:
		"ObjectTool","ScatterTool","WallTool","PortalTool","objects","portals","walls":
			texture = node.Texture
		"PathTool", "LightTool","paths","lights":
			texture = node.get_texture()
		"PatternShapeTool","pattern_shapes":
			texture = node._Texture
		"RoofTool","roofs":
			texture = node.TilesTexture
		_:
			return null

	return texture

# Function to look at resource string and return the texture
func load_image_texture(texture_path: String):

	var image = Image.new()
	var texture = ImageTexture.new()

	# If it isn't an internal resource
	if not "res://" in texture_path:
		image.load(Global.Root + texture_path)
		texture.create_from_image(image)
	# If it is an internal resource then just use the ResourceLoader
	else:
		texture = ResourceLoader.load(texture_path)
	
	return texture

# Function to draw a pattern shape on the current level, points are defined in pixels
func draw_pattern(points: Array, texture: Texture, color: Color, layer: int):

	outputlog("draw_pattern",2)
	outputlog("points: " + str(points),2)
	outputlog("texture: " + str(texture),2)
	outputlog("color: " + str(color),2)
	outputlog("layer: " + str(layer),2)

	var node_id
	var patternshape

	# DrawPolygon doesn't return a Node or a node id but we know it must be the next one
	node_id = Global.World.nextNodeID
	Global.World.GetCurrentLevel().PatternShapes.DrawPolygon(points,false)

	# Reference the patternshape by the node id which must be the next one we guessed earlier
	patternshape = Global.World.GetNodeByID(node_id)
	if patternshape != null:
		outputlog("Found node with node_id: " + str(node_id),2)
		# Check its node type
		var type = get_node_type(patternshape)
		outputlog("Node type is: " + str(type),2)
		# Check that this is indeed a pattern shape
		if type == "pattern_shapes":
			# Set the relevant options
			patternshape.SetOptions(texture, color, 0.0)
			patternshape.SetLayer(layer)
		else:
			outputlog("type is not pattern_shape, something failed",2)
	else:
		outputlog("Failed to make pattern: " + str(points),2)

	return patternshape

#########################################################################################################
##
## TRANSFORM FUNCTIONS
##
#########################################################################################################

func convert_object_to_pattern(object: Node2D) -> bool:

	outputlog("convert_object_to_pattern: " + str(object),2)

	# Check that this is an object and return if not
	if get_node_type(object) != "objects":
		return false

	# Get the object's texture
	var texture = get_asset_texture(object,get_node_type(object))
	# If the texture is null for some reason then stop
	if texture == null:
		return false
	# Get the texture size in pixels
	var tex_size = texture.get_size()

	# Set the base rectangle points for the object texture
	var points = [Vector2(0,0),Vector2(tex_size.x,0),tex_size,Vector2(0,tex_size.y)]
	# Create a new pattern with the same texture as the object and the same layer
	var patternshape = draw_pattern(points, texture, Color.white, object.z_index)
	if patternshape == null:
		return false

	# Find the max scale, noting that mods that vary the scale between x & y will not function correctly with this
	var max_scale = max(abs(object.scale.x),abs(object.scale.x))
	# Define the pattern scale to be the same as the object scale
	patternshape.scale = object.scale

	# Define the offset starting as a default value
	var offset = Vector2.ZERO

	# If this is mirrored in the y axis, the update the offset
	if object.scale.x < 0.0:
		offset.x += tex_size.x
	# If this is mirrored in the x axis, the update the offset
	if object.scale.y < 0.0:
		offset.y += tex_size.y
	
	# Set the patternshap position as a rotation around the centre of the object as this is done in world uv
	patternshape.position = (offset * max_scale - tex_size * max_scale * 0.5).rotated(object.rotation) + object.position
	# Set the rotation as the same as the object rotation
	patternshape.rotation = object.rotation

	# If _Lib and ColourThings mod installed, then transform colourthings data from the object to the new pattern and trigger the refresh node via refresh_node_combined_shader signal
	apply_custom_data_to_new_pattern(object, patternshape)

	return true
	
# Function to transform any of the selected objects
func on_transform_selected_objects():

	outputlog("on_transform_selected_objects",2)
	var delete_list = []

	# Check if we are in the select tool
	if Global.Editor.ActiveToolName != "SelectTool":
		return

	# Check that the object options are visible and do nothing if not. Noting it shouldn't be possible to call this function if a non-object is selected.
	if not Global.Editor.Toolset.GetToolPanel("SelectTool").objectOptions.visible:
		return

	# If no objects are selected then do nothing
	if not Global.Editor.Tools["SelectTool"].Selected.size() > 0:
		return
	
	var store_selected = Global.Editor.Tools["SelectTool"].Selected
	Global.Editor.Tools["SelectTool"].ClearTransformSelection()
	
	# For each of the selected objects
	for node in store_selected:
		# Double check this really is an objects
		if get_node_type(node) == "objects":
			# Convert the object to a pattern checking whether it is successful or not
			if convert_object_to_pattern(node):
				if Global.World.HasNodeID(node.get_meta("node_id")):
					outputlog("Marking original object for deletion: " + str(node),2)
					delete_list.append(node)

	# Switch to the PatternShapeTool but wait 0.1 seconds to allow the frame counter to increment in other mods and avoid triggering auto colour/blur effects
	var timer = Timer.new()
	timer.autostart = false
	timer.one_shot = true
	Global.Editor.get_node("Windows").add_child(timer)

	timer.start(0.1)
	yield(timer,"timeout")
	# If the switch to PatternShape Tool button is pressed
	if switch_button.pressed:
		# Switch to Patternnshape Tool and set the edit points button to active
		Global.Editor.Toolset.Quickswitch("PatternShapeTool")
		Global.Editor.Tools["PatternShapeTool"].get_EditPoints().pressed = true
	
	Global.Editor.get_node("Windows").remove_child(timer)
	timer.queue_free()

	# Delete the objects marked for deletion
	for node in delete_list:
		# Check if the node is null
		if node != null:
			# Check if the world has that node
			if Global.World.HasNodeID(node.get_meta("node_id")):
				# Delete the node
				outputlog("Deleting object: " + str(node),2)
				Global.World.DeleteNodeByID(node.get_meta("node_id"))

# Function to apply custom data to new pattern
func apply_custom_data_to_new_pattern(object, patternshape):

	outputlog("apply_custom_data_to_new_pattern",2)

	# If _Lib installed
	if Engine.has_signal("_lib_register_mod"):
		if has_data(object.get_meta("node_id")):
			outputlog("object node_id: " + str(object.get_meta("node_id")),2)
			outputlog("pattern node_id: " + str(patternshape.get_meta("node_id")),2)
			var data = get_data(object.get_meta("node_id"))
			data["type"] = "pattern_shapes"
			if not data["shader_type"] in ["none","gradient"]:
				data["shader_type"] = "none"
			patternshape.SetOptions(patternshape._Texture, Color(data["colour"]), 0.0)
			data["colour"] = "ffffffff"
			# Note we have checked the existence of the data store in order to get into this look
			Global.ModMapData[COMBINED_DATA_STORE]["data"]["node-id-"+str(patternshape.get_meta("node_id"))] = data.duplicate(true)
			outputlog("new_data for pattern: " + str(data),2)
			Global.API.ModSignalingApi.emit_signal("refresh_node_combined_shader", patternshape)

#########################################################################################################
##
## COMBINED DATA FUNCTION
##
#########################################################################################################

# Function to check if there is a data entry with this node id
func has_data(node_id) -> bool:

	outputlog("has_data: " + str(node_id),3)

	# Error checking if the holding structures have not been created.
	if not Global.ModMapData.has(COMBINED_DATA_STORE):
		outputlog("no COMBINED_DATA_STORE",3)
		return false
	if not Global.ModMapData[COMBINED_DATA_STORE].has("data"):
		outputlog("no COMBINED_DATA_STORE['data']",3)
		return false

	if Global.ModMapData[COMBINED_DATA_STORE]["data"].has("node-id-"+str(node_id)):
		outputlog("has_data: true",3)
		return true
	else:
		return false

# Function to erase data with a specific node id
func erase_data(node_id: int):

	outputlog("erase_data: " + str(node_id),2)

	if has_data(node_id):
		Global.ModMapData[COMBINED_DATA_STORE]["data"].erase("node-id-"+str(node_id))


# Function to get the colour data from the modmapdata structure
func get_data(node_id):

	var data = {}

	if has_data(node_id):
		data = Global.ModMapData[COMBINED_DATA_STORE]["data"]["node-id-"+str(node_id)]
		# If this is a pattern or a wall then take the colour from the node's in built colour value
		if Global.World.HasNodeID(node_id):
			if data["type"] in ["pattern_shapes","walls"]:
				data["colour"] = get_dd_colour(Global.World.GetNodeByID(node_id), data["type"])
		return data
	else:
		return null


#########################################################################################################
##
## UI CREATION FUNCTION
##
#########################################################################################################

# Function to create the ui for changing the object into a pattern at the same place with the same texture
func make_change_object_to_pattern_ui():

	outputlog("make_change_object_to_pattern_ui")

	var vbox = Global.Editor.Toolset.GetToolPanel("SelectTool").objectOptions

	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)

	var button = Button.new()
	button.text = "Change Object to Pattern"
	button.hint_tooltip = "Press to transform selected object into a pattern with the same texture."
	button.icon = load_image_texture("icons/transform-icon.png")
	button.connect("pressed", self, "on_transform_selected_objects")

	hbox.add_child(button)
	
	switch_button = Button.new()
	switch_button.toggle_mode = true
	switch_button.pressed = true
	switch_button.hint_tooltip = "When enabled, after a transformation, the tool will switch to the PatternTool for editing points."
	switch_button.icon = load_image_texture("res://ui/icons/tools/pattern_shape_tool.png")
	hbox.add_child(switch_button)


#########################################################################################################
##
## UPDATE FUNCTION
##
#########################################################################################################

# this method is automatically called every frame. delta is a float in seconds. can be removed from script.
func update(delta: float):

	pass

#########################################################################################################
##
## START FUNCTION FUNCTION
##
#########################################################################################################

# Main Script
func start() -> void:

	outputlog("ConvertObjectIntoPattern Mod Has been loaded.")

	if Engine.has_signal("_lib_register_mod"):
		Engine.emit_signal("_lib_register_mod", self)

	make_change_object_to_pattern_ui()


	

	
