'use strict'
#jslint node: true

#global describe, before, beforeEach, it

app = require("../../website/src/server")
User = require("../../website/src/models/user").model
Group = require("../../website/src/models/group").model
Challenge = require("../../website/src/models/challenge").model

describe "API", ->

  before (done) ->
    require "../../website/src/server" # start the server
    # then wait for it to do it's thing. TODO make a cb-compatible export of server
    setTimeout done, 2000

  describe "Challenges", ->
    challenge = undefined
    updateTodo = undefined
    group = undefined
    before (done) ->
      async.waterfall [
        (cb) ->
          registerNewUser(cb, true)
        , (user, cb) ->
          request.post(baseURL + "/groups").send(
            name: "TestGroup"
            type: "party"
          ).end (res) ->
            expectCode res, 200
            group = res.body
            expect(group.members.length).to.be 1
            expect(group.leader).to.be user._id
            done()
          ]
    it "Creates a challenge", (done) ->
      request.post(baseURL + "/challenges").send(
        group: group._id
        dailys: [
          type: "daily"
          text: "Challenge Daily"
        ]
        todos: [{
          type: "todo"
          text: "Challenge Todo 1"
          notes: "Challenge Notes"
        }, {
          type: "todo"
          text: "Challenge Todo 2"
          notes: "Challenge Notes"
        }]
        rewards: []
        habits: []
        official: true
      ).end (res) ->
        expectCode res, 200
        async.parallel [
          (cb) ->
            User.findById user._id, cb
          (cb) ->
            Challenge.findById res.body._id, cb
        ], (err, results) ->
          _user = results[0]
          challenge = results[1]
          expect(_user.dailys[_user.dailys.length - 1].text).to.be "Challenge Daily"
          updateTodo = _user.todos[_user.todos.length - 1]
          expect(updateTodo.text).to.be "Challenge Todo 2"
          expect(challenge.official).to.be false
          user = _user
          done()

    it "User updates challenge notes", (done) ->
      updateTodo.notes = "User overriden notes"
      request.put(baseURL + "/user/tasks/" + updateTodo.id).send(updateTodo).end (res) ->
        done() # we'll do the check down below

    it "Change challenge daily", (done) ->
      challenge.dailys[0].text = "Updated Daily"
      challenge.todos[0].notes = "Challenge Updated Todo Notes"
      request.post(baseURL + "/challenges/" + challenge._id).send(challenge).end (res) ->
        setTimeout (->
          User.findById user._id, (err, _user) ->
            expectCode res, 200
            expect(_user.dailys[_user.dailys.length - 1].text).to.be "Updated Daily"
            expect(res.body.todos[0].notes).to.be "Challenge Updated Todo Notes"
            expect(_user.todos[_user.todos.length - 1].notes).to.be "User overriden notes"
            user = _user
            done()
        ), 500 # we have to wait a while for users' tasks to be updated, called async on server

    it "Shows user notes on challenge page", (done) ->
      request.get(baseURL + "/challenges/" + challenge._id + "/member/" + user._id).end (res) ->
        expect(res.body.todos[res.body.todos.length - 1].notes).to.be "User overriden notes"
        done()

    it "Complete To-Dos", (done) ->
      User.findById user._id, (err, _user) ->
        u = _user
        numTasks = (_.size(u.todos))
        request.post(baseURL + "/user/tasks/" + u.todos[0].id + "/up").end (res) ->
          request.post(baseURL + "/user/tasks/clear-completed").end (res) ->
            expect(_.size(res.body)).to.be numTasks - 1
            done()

    it "Challenge deleted, breaks task link", (done) ->
      itThis = this
      request.del(baseURL + "/challenges/" + challenge._id).end (res) ->
        User.findById user._id, (err, user) ->
          len = user.dailys.length - 1
          daily = user.dailys[user.dailys.length - 1]
          expect(daily.challenge.broken).to.be "CHALLENGE_DELETED"

          # Now let's handle if challenge was deleted, but didn't get to update all the users (an error)
          unset = $unset: {}
          unset["$unset"]["dailys." + len + ".challenge.broken"] = 1
          User.findByIdAndUpdate user._id, unset, (err, user) ->
            expect(err).to.not.be.ok()
            expect(user.dailys[len].challenge.broken).to.not.be.ok()
            request.post(baseURL + "/user/tasks/" + daily.id + "/up").end (res) ->
              setTimeout (->
                User.findById user._id, (err, user) ->
                  expect(user.dailys[len].challenge.broken).to.be "CHALLENGE_DELETED"
                  done()
              ), 100 # we need to wait for challenge to update user, it's a background job for perf reasons

    it "Admin creates a challenge", (done) ->
      User.findByIdAndUpdate user._id,
        $set:
          "contributor.admin": true
      , (err, _user) ->
        expect(err).to.not.be.ok()
        async.parallel [
          (cb) ->
            request.post(baseURL + "/challenges").send(
              group: group._id
              dailys: []
              todos: []
              rewards: []
              habits: []
              official: false
            ).end (res) ->
              expect(res.body.official).to.be false
              cb()
          (cb) ->
            request.post(baseURL + "/challenges").send(
              group: group._id
              dailys: []
              todos: []
              rewards: []
              habits: []
              official: true
            ).end (res) ->
              expect(res.body.official).to.be true
              cb()
        ], done
