-- wrk script: hit random user IDs between 1 and 1000
request = function()
  local id = math.random(1, 1000)
  return wrk.format("GET", "/users/" .. id)
end
