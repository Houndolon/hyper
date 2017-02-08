module Site3 where

import Prelude
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Console (log, CONSOLE)
import Control.Monad.Error.Class (throwError)
import Control.Monad.Except (ExceptT)
import Data.Argonaut (class EncodeJson, Json, encodeJson, fromArray, jsonEmptyObject, (:=), (~>))
import Data.Array (find)
import Data.Maybe (Maybe(..), maybe)
import Data.MediaType.Common (textHTML)
import Hyper.Core (Port(Port), closeHeaders, writeStatus)
import Hyper.HTML (class EncodeHTML, HTML, element_, h1, li, linkTo, p, text, ul)
import Hyper.Node.Server (defaultOptions, runServer)
import Hyper.Response (contentType, respond)
import Hyper.Routing (type (:/), type (:<|>), type (:>), Capture, (:<|>))
import Hyper.Routing.Links (linksTo)
import Hyper.Routing.Method (Get)
import Hyper.Routing.Router (RoutingError(..), router)
import Hyper.Status (statusNotFound)
import Node.Buffer (BUFFER)
import Node.HTTP (HTTP)
import Type.Proxy (Proxy(..))

data Home = Home

newtype User = User { id :: Int, name :: String }

instance encodeJsonUser :: EncodeJson User where
  encodeJson (User { id, name }) =
    "id" := show id
    ~> "name" := name
    ~> jsonEmptyObject


data AllUsers = AllUsers (Array User)

instance encodeJsonAllUsers :: EncodeJson AllUsers where
  encodeJson (AllUsers users) = fromArray (map encodeJson users)

type Site3 =
  Get HTML Home
  :<|> "users" :/ Get (HTML :<|> Json) AllUsers
  :<|> "users" :/ Capture "user-id" Int :> Get (HTML :<|> Json) User

site3 :: Proxy Site3
site3 = Proxy

home :: forall m. Monad m => ExceptT RoutingError m Home
home = pure Home

allUsers :: forall m. Monad m => ExceptT RoutingError m AllUsers
allUsers = AllUsers <$> getUsers

getUser :: forall m. Monad m => Int -> ExceptT RoutingError m User
getUser id' =
  find userWithId <$> getUsers >>=
  case _ of
    Just user -> pure user
    Nothing ->
      throwError (HTTPError { status: statusNotFound
                            , message: Just "User not found."
                            })
  where
    userWithId (User u) = u.id == id'

instance encodeHTMLHome :: EncodeHTML Home where
  encodeHTML Home =
    case linksTo site3 of
      _ :<|> allUsers' :<|> _ ->
        p [] [ text "Welcome to my site! Go check out my "
             , linkTo allUsers' [ text "Users" ]
             , text "."
             ]

instance encodeHTMLAllUsers :: EncodeHTML AllUsers where
  encodeHTML (AllUsers users) =
    element_ "div" [ h1 [] [ text "Users" ]
                   , ul [] (map linkToUser users)
                   ]
    where
      linkToUser (User u) =
        case linksTo site3 of
          _ :<|> _ :<|> getUser' ->
            li [] [ linkTo (getUser' u.id) [ text u.name ] ]

instance encodeHTMLUser :: EncodeHTML User where
  encodeHTML (User { name }) =
    h1 [] [ text name ]

getUsers :: forall m. Applicative m => m (Array User)
getUsers =
  pure
  [ User { id: 1, name: "John Paul Jones" }
  , User { id: 2, name: "Tal Wilkenfeld" }
  , User { id: 3, name: "John Patitucci" }
  , User { id: 4, name: "Jaco Pastorious" }
  ]

main :: forall e. Eff (http :: HTTP, console :: CONSOLE, buffer :: BUFFER | e) Unit
main =
  let site3Router =
        router site3 (home :<|> allUsers :<|> getUser) onRoutingError

      onRoutingError status msg =
        writeStatus status
        >=> contentType textHTML
        >=> closeHeaders
        >=> respond (maybe "" id msg)

      onListening (Port port) =
        log ("Listening on http://localhost:" <> show port)

      onRequestError err =
        log ("Request failed: " <> show err)

  in runServer defaultOptions onListening onRequestError {} site3Router