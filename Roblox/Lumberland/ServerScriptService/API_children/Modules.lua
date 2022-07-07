local KDKit = require(game.ReplicatedStorage:WaitForChild("KDKit"))

return KDKit.LazyRequire(
    script,
    { "Config", "JobId", "OTPAuth", "Time", "URL", "Error" }
)
