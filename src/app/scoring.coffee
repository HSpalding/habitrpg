content = require('./content')

# Calculates Exp modification based on weapon & lvl
expModifier = (user, value) ->
  dmg = user.get('items.weapon') * .03 # each new weapon adds an additional 3% experience
  dmg += user.get('stats.lvl') * .03 # same for lvls
  modified = value + (value * dmg)
  return modified

# Calculates HP-loss modification based on armor & lvl
hpModifier = (user, value) ->
  ac = user.get('items.armor') * .03 # each new armor blocks an additional 3% damage
  ac += user.get('stats.lvl') * .03 # same for lvls
  modified = value - (value * ac)
  return modified
  
# Setter for user.stats: handles death, leveling up, etc
updateStats = (user, stats) ->
  if stats.hp?
    # game over
    if stats.hp < 0
      user.set 'stats.lvl', 0 # this signifies dead
    else
      user.set 'stats.hp', stats.hp

  if stats.exp?
    # level up & carry-over exp
    tnl = user.get '_tnl'
    if stats.exp >= tnl
      stats.exp -= tnl
      user.set 'stats.lvl', user.get('stats.lvl') + 1
    if !user.get('items.itemsEnabled') and stats.exp >=50
      user.set 'items.itemsEnabled', true
      $('ul.items').popover
        title: content.items.unlockedMessage.title
        placement: 'left'
        trigger: 'manual'
        html: true
        content: "<div class='item-store-popover'>\
          <img src='/img/BrowserQuest/chest.png' />\
          #{content.items.unlockedMessage.content} <a href='#' onClick=\"$('ul.items').popover('hide');return false;\">[Close]</a>\
          </div>"
      $('ul.items').popover 'show'

    user.set 'stats.exp', stats.exp
    
  if stats.money?
    money = 0.0 if (!money? or money<0)
    user.set 'stats.money', stats.money
    
module.exports.score = (spec = {user:null, task:null, direction:null, cron:null}) ->
  # console.log spec, "scoring.coffee: score( ->spec<- )" 
  [user, task, direction, cron] = [spec.user, spec.task, spec.direction, spec.cron]
  
  # For negative values, use a line: something like y=-.1x+1
  # For positibe values, taper off with inverse log: y=.9^x
  # Would love to use inverse log for the whole thing, but after 13 fails it hits infinity
  sign = if (direction == "up") then 1 else -1
  value = task.get('value')
  delta = if (value < 0) then (( -0.1 * value + 1 ) * sign) else (( Math.pow(0.9,value) ) * sign)
  
  type = task.get('type')

  # Don't adjust values for rewards, or for habits that don't have both + and -
  adjustvalue = (type != 'reward')
  if (type == 'habit') and (task.get("up")==false or task.get("down")==false)
    adjustvalue = false
  value += delta if adjustvalue

  if type == 'habit'
    # Add habit value to habit-history (if different)
    task.push 'history', { date: new Date(), value: value } if task.get('value') != value
  task.set('value', value)

  # Update the user's status
  [money, hp, exp, lvl] = [user.get('stats.money'), user.get('stats.hp'), user.get('stats.exp'), user.get('stats.lvl')]

  if type == 'reward'
    # purchase item
    money -= task.get('value')
    # if too expensive, reduce health & zero money
    if money < 0
      hp += money # hp - money difference
      money = 0
      
  # Add points to exp & money if positive delta
  # Only take away mony if it was a mistake (aka, a checkbox)
  if (delta > 0 or ( type in ['daily', 'todo'])) and !cron
    exp += expModifier(user, delta)
    money += delta
  # Deduct from health (rewards case handled above)
  else unless type in ['reward', 'todo']
    hp += hpModifier(user, delta)

  updateStats(user, {hp: hp, exp: exp, money: money})
  
  return delta 

# At end of day, add value to all incomplete Daily & Todo tasks (further incentive)
# For incomplete Dailys, deduct experience
module.exports.tally = (model) ->
  # users = model.at('users') #TODO this isn't working, iterate over all users
  # for user in users
  user = model.at '_user'
  todoTally = 0
  for key of model.get '_user.tasks'
    task = model.at "_user.tasks.#{key}"
    [type, value, completed] = [task.get('type'), task.get('value'), task.get('completed')] 
    if type in ['todo', 'daily']
      # Deduct experience for missed Daily tasks, 
      # but not for Todos (just increase todo's value)
      module.exports.score({user:user, task:task, direction:'down', cron:true}) unless completed
      if type == 'daily'
        task.push "history", { date: new Date(), value: value }
      else
        absVal = if (completed) then Math.abs(value) else value
        todoTally += absVal
      task.pass({cron:true}).set('completed', false) if type == 'daily'
  model.push '_user.history.todos', { date: new Date(), value: todoTally }
  
  # tally experience
  expTally = user.get 'stats.exp'
  lvl = 0 #iterator
  while lvl < (user.get('stats.lvl')-1)
    lvl++
    expTally += 50 * Math.pow(lvl, 2) - 150 * lvl + 200
  model.push '_user.history.exp',  { date: new Date(), value: expTally } 