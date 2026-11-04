--!strict
-- Poses skinned enemy meshes locally, in the same frame as the interpolated enemy root.
type Joint = { bone: Bone, kind: string, side: number, x: Vector3, y: Vector3, z: Vector3, lower: number }
export type Rig = { joints: { Joint }, nextPose: number }

local RigMotion = {}
local JOINTS: { [string]: string } = {
	hips = "Hips", pelvis = "Hips",
	spine = "Spine", spine1 = "Spine",
	head = "Head",
	upperleg = "Thigh", upleg = "Thigh", thigh = "Thigh",
	lowerleg = "Knee", leg = "Knee", calf = "Knee", shin = "Knee",
	foot = "Foot",
	upperarm = "Shoulder", arm = "Shoulder",
	lowerarm = "Elbow", forearm = "Elbow",
}

local function jointName(name: string): (string?, number)
	local key = string.lower(name):gsub("[^%w]", "")
	key = key:gsub("^mixamorig%d*", ""):gsub("^armature", "")
	local side = 0
	if key:sub(1, 4) == "left" then
		key, side = key:sub(5), -1
	elseif key:sub(1, 5) == "right" then
		key, side = key:sub(6), 1
	elseif key:sub(-1) == "l" and JOINTS[key:sub(1, -2)] then
		key, side = key:sub(1, -2), -1
	elseif key:sub(-1) == "r" and JOINTS[key:sub(1, -2)] then
		key, side = key:sub(1, -2), 1
	end
	return JOINTS[key], side
end

function RigMotion.bind(model: Instance, facing: CFrame): Rig
	local rig: Rig = { joints = {}, nextPose = 0 }
	for _, bone in model:GetDescendants() do
		if not bone:IsA("Bone") then
			continue
		end
		local kind, side = jointName(bone.Name)
		if not kind then
			continue
		end
		local rest = bone.WorldCFrame
		local lower = 0
		if kind == "Shoulder" then
			local elbow = bone:FindFirstChildWhichIsA("Bone")
			if elbow then
				local arm = facing:VectorToObjectSpace(elbow.WorldPosition - bone.WorldPosition)
				side = if arm.X >= 0 then 1 else -1
				lower = -math.atan2(arm.X, -arm.Y) * .90
			end
		elseif kind == "Elbow" then
			local hand = bone:FindFirstChildWhichIsA("Bone")
			if hand then
				side = if facing:VectorToObjectSpace(hand.WorldPosition - bone.WorldPosition).X >= 0 then 1 else -1
			end
		end
		table.insert(rig.joints, {
			bone = bone, kind = kind, side = side, lower = lower,
			x = rest:VectorToObjectSpace(facing.RightVector),
			y = rest:VectorToObjectSpace(facing.UpVector),
			z = rest:VectorToObjectSpace(-facing.LookVector),
		})
	end
	return rig
end

local function golemAngles(joint: Joint, swing: number, lift: number, step: number, windup: number, impact: number): (number, number, number)
	local kind = joint.kind
	if kind == "Shoulder" then
		return .18 - swing * .30 + windup * 2.30 - impact * .34, 0, joint.lower * .80
	elseif kind == "Elbow" then
		return 0, joint.side * (.16 + windup * .42 + impact * .11), 0
	elseif kind == "Thigh" then
		return swing * .42 + lift * .09 + impact * .19, 0, 0
	elseif kind == "Knee" then
		return -lift * .36 - windup * .16 - impact * .33, 0, 0
	elseif kind == "Foot" then
		return lift * .15 - swing * .08, 0, 0
	elseif kind == "Spine" then
		return -.04 + windup * .18 - impact * .31, -.10 * step, 0
	elseif kind == "Head" then
		return .03 - windup * .20 + impact * .12, 0, step * .03
	end
	return 0, .08 * step, 0
end

function RigMotion.apply(rig: Rig, name: string, phase: number, weight: number, windup: number, strike: number, now: number)
	if now < rig.nextPose then
		return
	end
	rig.nextPose = now + 1 / 30
	local zombie = name == "Zombie"
	local ghost = name == "SurveillantFantome"
	local golem = name == "Golem"
	local step = math.sin(phase) * weight
	local rhythm = math.cos(phase)
	local action = math.sin(math.pi * math.clamp(strike, 0, 1) ^ .55)
	for _, joint in rig.joints do
		local side = joint.side
		local swing = step * side
		local lift = math.max(0, rhythm * side) * weight
		local pitch, twist, roll = 0, 0, 0
		if golem then
			pitch, twist, roll = golemAngles(joint, swing, lift, step, windup, action)
		elseif joint.kind == "Thigh" then
			local stride = if ghost then .30 elseif zombie then (if side < 0 then .51 else .31) else .79
			pitch = swing * stride + lift * (if zombie then .08 else .15) + action * (if side < 0 then .17 else -.14)
		elseif joint.kind == "Knee" then
			pitch = -lift * (if zombie then .36 elseif ghost then .38 else .82) - windup * .19
		elseif joint.kind == "Foot" then
			pitch = lift * .22 - swing * .12
		elseif joint.kind == "Shoulder" then
			roll = joint.lower * (if ghost then .76 else 1)
			if zombie then
				pitch = 1.00 - swing * .19 + action * .48 - windup * .38
			elseif ghost then
				pitch = .23 - swing * .30 + action * 1.09 - windup * .36
				roll *= 1 - windup * .55
			else
				pitch = -swing * .68 + (if side > 0 then action * 1.30 - windup * .55 else -action * .28)
				roll -= side * action * .23
			end
		elseif joint.kind == "Elbow" then
			twist = side * (if zombie then .18 - action * .10
				elseif ghost then .35 + windup * .62 - action * .27
				else .30 + lift * .29 + windup * .55 - action * .18)
		elseif joint.kind == "Hips" then
			twist = step * .09
		elseif joint.kind == "Spine" then
			pitch = (if zombie then -.12 elseif ghost then 0 else -.18) + windup * .25 - action * .31
			twist = step * -.12 + action * (if ghost then -.07 else .31)
		elseif joint.kind == "Head" then
			pitch = (if zombie then .11 else .05) + windup * .12
			roll = step * (if zombie then .14 else .05)
		end
		joint.bone.Transform = CFrame.fromAxisAngle(joint.x, pitch)
			* CFrame.fromAxisAngle(joint.y, twist)
			* CFrame.fromAxisAngle(joint.z, roll)
	end
end

return RigMotion
